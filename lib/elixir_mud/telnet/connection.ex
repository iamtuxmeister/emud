defmodule ElixirMud.Telnet.Connection do
  @moduledoc """
  Per-connection process — implements both the Ranch `:ranch_protocol`
  behaviour and a plain GenServer.

  Lifecycle
  ---------
    1. Ranch accepts a TCP socket and calls `start_link/3`.
    2. `init/1` takes Ranch socket control, sets `{active, :once}`.
    3. `handle_info({:tcp, …})` feeds bytes into the Telnet parser.
    4. Parser events are dispatched to protocol handlers.
    5. Plain-text input is forwarded to the `Session` process.
    6. `handle_info({:tcp_closed, …})` / `{:tcp_error, …}` clean up.

  Sending data
  ------------
  Other processes can send text to a connection with:

      ElixirMud.Telnet.Connection.send_text(pid, "You see a dragon.")

  The call goes through `handle_cast/2` so the send is serialised on
  the connection process, preventing interleaved writes.

  Adding new telnet options
  -------------------------
  1. Add an `offer_option/1` call in `do_telnet_handshake/1`.
  2. Add a clause to `handle_event/2` for `{:do, opt}` / `{:will, opt}`.
  3. Implement your handler module and call it from `handle_event/2`.
  """

  use GenServer
  require Logger

  alias ElixirMud.Telnet.{Protocol, Options, MCCP2, GMCP, MSDP}

  @behaviour :ranch_protocol

  # How long (ms) to wait for the ranch handshake before giving up
  @handshake_timeout 5_000

  defstruct [
    :socket,
    :transport,
    :session_pid,
    protocol:  nil,   # %Protocol{}
    mccp2:     nil,   # %MCCP2{}
    gmcp:      nil,   # GMCP state map
    msdp:      nil,   # MSDP state map
    naws:      nil,   # {cols, rows} or nil
    ttype:     nil    # terminal type string or nil
  ]

  # ─── Ranch protocol entry point ───────────────────────────────────────────

  @impl :ranch_protocol
  def start_link(ref, transport, opts) do
    GenServer.start_link(__MODULE__, {ref, transport, opts})
  end

  # ─── GenServer init ───────────────────────────────────────────────────────

  @impl GenServer
  def init({ref, transport, _opts}) do
    # Ranch handshake must happen before we do anything with the socket
    {:ok, socket} = :ranch.handshake(ref, @handshake_timeout)

    state = %__MODULE__{
      socket:    socket,
      transport: transport,
      protocol:  Protocol.new(),
      mccp2:     MCCP2.new(),
      gmcp:      GMCP.new(),
      msdp:      MSDP.new()
    }

    # Activate the socket so we receive TCP messages as {:tcp, …}
    :ok = transport.setopts(socket, active: :once, packet: :raw)

    # Start the Telnet option handshake and send welcome banner
    state = do_telnet_handshake(state)
    state = send_welcome(state)

    {:ok, state}
  end

  # ─── Public API ───────────────────────────────────────────────────────────

  @doc "Send plain text to this connection (may be compressed if MCCP2 active)."
  def send_text(pid, text) when is_binary(text) do
    GenServer.cast(pid, {:send_text, text})
  end

  @doc "Send a pre-built GMCP message to this connection."
  def send_gmcp(pid, package, data \\ nil) do
    GenServer.cast(pid, {:send_gmcp, package, data})
  end

  @doc "Send a pre-built MSDP message to this connection."
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
    bytes = MSDP.build_message(vars)
    {:noreply, do_send_raw(state, bytes)}
  end

  # ─── handle_info — TCP events ─────────────────────────────────────────────

  @impl GenServer
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    # Re-arm the socket for the next packet
    :ok = state.transport.setopts(socket, active: :once)

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

  # Plain text from the client — forward to session
  defp handle_event(state, {:data, text}) do
    if state.session_pid do
      send(state.session_pid, {:input, text})
    else
      # No session yet — echo back for debugging / future login handler
      do_send(state, text)
    end
    state
  end

  # ── Option negotiation ────────────────────────────────────────────────────

  # Client agrees to receive GMCP
  defp handle_event(state, {:do, Options.opt_gmcp()}) do
    Logger.debug("GMCP enabled by client")
    gmcp = GMCP.enable(state.gmcp)
    # Send Core.Hello
    state = %{state | gmcp: gmcp}
    case GMCP.core_hello() do
      {:ok, bytes} -> do_send_raw(state, bytes)
      _            -> state
    end
  end

  # Client declines GMCP
  defp handle_event(state, {:dont, Options.opt_gmcp()}) do
    Logger.debug("Client refused GMCP")
    state
  end

  # Client agrees to receive MSDP
  defp handle_event(state, {:do, Options.opt_msdp()}) do
    Logger.debug("MSDP enabled by client")
    msdp = MSDP.enable(state.msdp)
    state = %{state | msdp: msdp}
    # Advertise reportable variables
    bytes = MSDP.reportable_variables(["ROOM", "CHAR", "WORLD"])
    do_send_raw(state, bytes)
  end

  # Client agrees to compression (MCCP2)
  defp handle_event(state, {:do, Options.opt_mccp2()}) do
    Logger.debug("MCCP2 enabled by client")
    {mccp2, handshake} = MCCP2.enable(state.mccp2)
    state = %{state | mccp2: mccp2}
    # Handshake must be sent uncompressed — use raw transport
    raw_send(state, handshake)
    state
  end

  defp handle_event(state, {:dont, Options.opt_mccp2()}) do
    Logger.debug("Client refused MCCP2")
    state
  end

  # Client reports terminal type
  defp handle_event(state, {:will, Options.opt_ttype()}) do
    # Ask for the terminal type
    req = <<Options.iac()::8, Options.sb()::8, Options.opt_ttype()::8, 1::8,
            Options.iac()::8, Options.se()::8>>
    do_send_raw(state, req)
    state
  end

  # Terminal type subneg response
  defp handle_event(state, {:subneg, Options.opt_ttype(), <<0::8, ttype::binary>>}) do
    Logger.debug("Terminal type: #{ttype}")
    %{state | ttype: ttype}
  end

  # Client reports window size (NAWS)
  defp handle_event(state, {:will, Options.opt_naws()}) do
    state
  end

  defp handle_event(state, {:subneg, Options.opt_naws(), <<cols::16, rows::16>>}) do
    Logger.debug("Window size: #{cols}x#{rows}")
    %{state | naws: {cols, rows}}
  end

  # Client sends GMCP subneg
  defp handle_event(state, {:subneg, Options.opt_gmcp(), payload}) do
    {gmcp, action} = GMCP.handle_subneg(state.gmcp, payload)
    state = %{state | gmcp: gmcp}
    apply_action(state, action)
  end

  # Client sends MSDP subneg
  defp handle_event(state, {:subneg, Options.opt_msdp(), payload}) do
    {msdp, actions} = MSDP.handle_subneg(state.msdp, payload)
    state = %{state | msdp: msdp}
    Enum.reduce(actions, state, &apply_action(&2, &1))
  end

  # Gracefully decline anything we don't know
  defp handle_event(state, {:will, opt}) do
    Logger.debug("Sending DONT for unknown option #{opt}")
    raw_send(state, Options.dont(opt))
    state
  end

  defp handle_event(state, {:do, opt}) do
    Logger.debug("Sending WONT for unknown option #{opt}")
    raw_send(state, Options.wont(opt))
    state
  end

  defp handle_event(state, _event), do: state

  # ─── Action helpers ───────────────────────────────────────────────────────

  defp apply_action(state, :ok), do: state

  defp apply_action(state, {:send, bytes}) do
    do_send_raw(state, bytes)
  end

  defp apply_action(state, {:event, event}) do
    if state.session_pid, do: send(state.session_pid, event)
    state
  end

  defp apply_action(state, actions) when is_list(actions) do
    Enum.reduce(actions, state, &apply_action(&2, &1))
  end

  # ─── Telnet handshake ─────────────────────────────────────────────────────

  defp do_telnet_handshake(state) do
    # Announce what we support; client will reply DO/DONT for each
    opts = [
      Options.will(Options.opt_gmcp()),
      Options.will(Options.opt_msdp()),
      Options.will(Options.opt_mccp2()),
      Options.do_(Options.opt_ttype()),
      Options.do_(Options.opt_naws()),
      Options.will(Options.opt_suppress_go_ahead()),
      Options.do_(Options.opt_suppress_go_ahead())
    ]

    Enum.each(opts, &raw_send(state, &1))
    state
  end

  # ─── Welcome banner ───────────────────────────────────────────────────────

  defp send_welcome(state) do
    banner = Application.get_env(:elixir_mud, :welcome_banner, "Welcome to ElixirMUD\n\n")
    do_send(state, banner)
  end

  # ─── Low-level send ───────────────────────────────────────────────────────

  # Send text, applying MCCP2 compression if active
  defp do_send(state, text) do
    bytes = MCCP2.compress(state.mccp2, text)
    raw_send(state, bytes)
    state
  end

  # Send pre-built protocol bytes (IAC sequences etc.) — also compressed
  defp do_send_raw(state, bytes) do
    compressed = MCCP2.compress(state.mccp2, bytes)
    raw_send(state, compressed)
    state
  end

  # Bypass compression — use only for MCCP2 handshake and pre-compression bytes
  defp raw_send(state, bytes) do
    case state.transport.send(state.socket, bytes) do
      :ok              -> :ok
      {:error, reason} -> Logger.warning("Send failed: #{inspect(reason)}")
    end
  end

  # ─── Cleanup ──────────────────────────────────────────────────────────────

  defp cleanup(state) do
    MCCP2.disable(state.mccp2)
    state.transport.close(state.socket)
    state
  end
end
