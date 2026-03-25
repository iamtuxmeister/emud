defmodule Emud.Telnet.Connection do
  @moduledoc """
  Per-connection process — implements both the Ranch `:ranch_protocol`
  behaviour and a plain GenServer.

  ## Ranch 2.x + GenServer handshake ordering

  `init/1` must return immediately (giving Ranch the pid it needs), so
  the actual handshake is deferred to `handle_continue(:post_init, …)`,
  which runs before any other message is processed.

  ## Lifecycle
    1. Ranch acceptor calls `start_link/3`.
    2. `init/1` stashes {ref, transport}, returns `{:continue, :post_init}`.
    3. `handle_continue/2` calls `ranch:handshake/1`, activates socket.
    4. Telnet option burst + welcome banner sent.
    5. `handle_info({:tcp, …})` feeds bytes into the Telnet parser.
    6. Parser events dispatched to protocol handlers (GMCP, MSDP, MCCP2).
    7. Plain-text input forwarded to the `Session` process (once one exists).
    8. `{:tcp_closed, …}` / `{:tcp_error, …}` clean up.

  ## Adding new telnet options
    1. Add a `will/do` send in `do_telnet_handshake/1`.
    2. Add a `handle_event/2` clause for `{:do, opt}` / `{:will, opt}`.
    3. Implement a handler module; call it from `handle_event/2`.
  """

  use GenServer
  require Logger
  require Emud.Telnet.Options, as: Options

  alias Emud.Telnet.{Protocol, Options, MCCP2, GMCP, MSDP}

  @behaviour :ranch_protocol

  defstruct [
    :ref,           # Ranch listener ref — used only during handshake
    :socket,
    :transport,
    :session_pid,
    protocol:  nil,
    mccp2:     nil,
    gmcp:      nil,
    msdp:      nil,
    naws:      nil,
    ttype:     nil
  ]

  # ─── Ranch protocol entry point ───────────────────────────────────────────

  @impl :ranch_protocol
  def start_link(ref, transport, opts) do
    GenServer.start_link(__MODULE__, {ref, transport, opts})
  end

  # ─── GenServer init ───────────────────────────────────────────────────────

  @impl GenServer
  def init({ref, transport, _opts}) do
    state = %__MODULE__{
      ref:       ref,
      transport: transport,
      protocol:  Protocol.new(),
      mccp2:     MCCP2.new(),
      gmcp:      GMCP.new(),
      msdp:      MSDP.new()
    }
    {:ok, state, {:continue, :post_init}}
  end

  # ─── Post-init: handshake, activate socket, greet ─────────────────────────

  @impl GenServer
  def handle_continue(:post_init, %{ref: ref, transport: transport} = state) do
    {:ok, socket} = :ranch.handshake(ref)
    state = %{state | ref: nil, socket: socket}
    :ok = transport.setopts(socket, [{:active, :once}, {:packet, :raw}])
    state = do_telnet_handshake(state)
    state = send_welcome(state)
    {:noreply, state}
  end

  # ─── Public API ───────────────────────────────────────────────────────────

  @doc "Send plain text to this connection (compressed if MCCP2 active)."
  def send_text(pid, text) when is_binary(text) do
    GenServer.cast(pid, {:send_text, text})
  end

  @doc "Send a GMCP package to this connection."
  def send_gmcp(pid, package, data \\ nil) do
    GenServer.cast(pid, {:send_gmcp, package, data})
  end

  @doc "Send MSDP variables to this connection."
  def send_msdp(pid, vars) when is_map(vars) do
    GenServer.cast(pid, {:send_msdp, vars})
  end

  # ─── handle_cast ──────────────────────────────────────────────────────────

  @impl GenServer
  def handle_cast({:send_text, text}, state) do
    {:noreply, do_send(state, text)}
  end

  def handle_cast({:send_gmcp, package, data}, state) do
    case GMCP.build_message(package, data) do
      {:ok, bytes} -> {:noreply, do_send_raw(state, bytes)}
      {:error, _}  -> {:noreply, state}
    end
  end

  def handle_cast({:send_msdp, vars}, state) do
    {:noreply, do_send_raw(state, MSDP.build_message(vars))}
  end

  # ─── handle_info — TCP events ─────────────────────────────────────────────

  @impl GenServer
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    :ok = state.transport.setopts(socket, [{:active, :once}])
    {protocol, events} = Protocol.feed(state.protocol, data)
    state = %{state | protocol: protocol}
    state = Enum.reduce(events, state, &handle_event(&2, &1))
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Connection closed")
    {:stop, :normal, cleanup(state)}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warning("TCP error: #{inspect(reason)}")
    {:stop, :normal, cleanup(state)}
  end

  # ─── Telnet event dispatcher ──────────────────────────────────────────────

  # Plain text — forward to session, or echo if no session yet
  defp handle_event(state, {:data, text}) do
    if state.session_pid do
      send(state.session_pid, {:input, text})
    else
      do_send(state, text)
    end
    state
  end

  # GMCP
  defp handle_event(state, {:do, Options.opt_gmcp()}) do
    Logger.debug("GMCP enabled")
    state = %{state | gmcp: GMCP.enable(state.gmcp)}
    case GMCP.core_hello() do
      {:ok, bytes} -> do_send_raw(state, bytes)
      _            -> state
    end
  end

  defp handle_event(state, {:dont, Options.opt_gmcp()}) do
    Logger.debug("GMCP refused")
    state
  end

  # MSDP
  defp handle_event(state, {:do, Options.opt_msdp()}) do
    Logger.debug("MSDP enabled")
    state = %{state | msdp: MSDP.enable(state.msdp)}
    do_send_raw(state, MSDP.reportable_variables(["ROOM", "CHAR", "WORLD"]))
  end

  # MCCP2
  defp handle_event(state, {:do, Options.opt_mccp2()}) do
    Logger.debug("MCCP2 enabled")
    {mccp2, handshake} = MCCP2.enable(state.mccp2)
    state = %{state | mccp2: mccp2}
    raw_send(state, handshake)   # must be sent uncompressed
    state
  end

  defp handle_event(state, {:dont, Options.opt_mccp2()}) do
    Logger.debug("MCCP2 refused")
    state
  end

  # Terminal type
  defp handle_event(state, {:will, Options.opt_ttype()}) do
    req = <<Options.iac()::8, Options.sb()::8, Options.opt_ttype()::8,
            1::8, Options.iac()::8, Options.se()::8>>
    do_send_raw(state, req)
    state
  end

  defp handle_event(state, {:subneg, Options.opt_ttype(), <<0::8, ttype::binary>>}) do
    Logger.debug("Terminal type: #{ttype}")
    %{state | ttype: ttype}
  end

  # NAWS
  defp handle_event(state, {:will, Options.opt_naws()}), do: state

  defp handle_event(state, {:subneg, Options.opt_naws(), <<cols::16, rows::16>>}) do
    Logger.debug("Window size: #{cols}x#{rows}")
    %{state | naws: {cols, rows}}
  end

  # GMCP subneg from client
  defp handle_event(state, {:subneg, Options.opt_gmcp(), payload}) do
    {gmcp, action} = GMCP.handle_subneg(state.gmcp, payload)
    apply_action(%{state | gmcp: gmcp}, action)
  end

  # MSDP subneg from client
  defp handle_event(state, {:subneg, Options.opt_msdp(), payload}) do
    {msdp, actions} = MSDP.handle_subneg(state.msdp, payload)
    Enum.reduce(actions, %{state | msdp: msdp}, &apply_action(&2, &1))
  end

  # Decline unknown options
  defp handle_event(state, {:will, opt}) do
    raw_send(state, Options.dont(opt))
    state
  end

  defp handle_event(state, {:do, opt}) do
    raw_send(state, Options.wont(opt))
    state
  end

  defp handle_event(state, _event), do: state

  # ─── Action helpers ───────────────────────────────────────────────────────

  defp apply_action(state, :ok), do: state
  defp apply_action(state, {:send, bytes}), do: do_send_raw(state, bytes)
  defp apply_action(state, {:event, event}) do
    if state.session_pid, do: send(state.session_pid, event)
    state
  end
  defp apply_action(state, actions) when is_list(actions) do
    Enum.reduce(actions, state, &apply_action(&2, &1))
  end

  # ─── Telnet option handshake ──────────────────────────────────────────────

  defp do_telnet_handshake(state) do
    burst = [
      Options.will(Options.opt_gmcp()),
      Options.will(Options.opt_msdp()),
      Options.will(Options.opt_mccp2()),
      Options.do_(Options.opt_ttype()),
      Options.do_(Options.opt_naws()),
      Options.will(Options.opt_suppress_go_ahead()),
      Options.do_(Options.opt_suppress_go_ahead())
    ]
    raw_send(state, IO.iodata_to_binary(burst))
    state
  end

  # ─── Welcome banner ───────────────────────────────────────────────────────

  defp send_welcome(state) do
    banner = Application.get_env(:emud, :welcome_banner, "Welcome to EMUD\n\n")
    do_send(state, banner)
  end

  # ─── Low-level send ───────────────────────────────────────────────────────

  defp do_send(state, text) do
    raw_send(state, MCCP2.compress(state.mccp2, text))
    state
  end

  defp do_send_raw(state, bytes) do
    raw_send(state, MCCP2.compress(state.mccp2, bytes))
    state
  end

  defp raw_send(state, bytes) do
    case state.transport.send(state.socket, bytes) do
      :ok              -> :ok
      {:error, reason} -> Logger.warning("Send failed: #{inspect(reason)}")
    end
  end

  # ─── Cleanup ──────────────────────────────────────────────────────────────

  defp cleanup(state) do
    if state.mccp2, do: MCCP2.disable(state.mccp2)
    if state.socket, do: state.transport.close(state.socket)
    state
  end
end
