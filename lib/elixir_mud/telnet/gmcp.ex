defmodule ElixirMud.Telnet.GMCP do
  @moduledoc """
  GMCP — Generic MUD Communication Protocol  (option 201).

  GMCP sends structured JSON data over subnegotiation.
  Each message has a package name and an optional JSON body:

      IAC SB GMCP "Package.Subpackage" <SPACE> {"json":"data"} IAC SE

  Packages used in this server
  -----------------------------
    Core.Hello       — server identification on connect
    Core.Supports    — client capability list (received from client)
    Char.Vitals      — HP/MP/MV updates  (example hook)
    Room.Info        — room description update  (example hook)

  Adding a new GMCP package
  -------------------------
  1. Add a `handle_package/3` clause below.
  2. Call `GMCP.send_package/3` from the connection or game logic.
  """

  require Logger

  @type state :: %{
    enabled: boolean(),
    client_supports: list(String.t())
  }

  @doc "Initial GMCP state."
  def new, do: %{enabled: false, client_supports: []}

  @doc "Mark GMCP as negotiated."
  def enable(state), do: %{state | enabled: true}

  # ─── Sending ──────────────────────────────────────────────────────────────

  @doc """
  Build a GMCP subnegotiation frame for `package` with `data`.
  `data` must be a term that Jason can encode, or nil for no body.

  Returns `{:ok, iodata}` or `{:error, reason}`.
  """
  @spec build_message(String.t(), term()) :: {:ok, iodata()} | {:error, term()}
  def build_message(package, data \\ nil) do
    payload =
      if is_nil(data) do
        package
      else
        case Jason.encode(data) do
          {:ok, json} -> "#{package} #{json}"
          {:error, _} = err -> return_error(err)
        end
      end

    case payload do
      {:error, _} = err -> err
      str -> {:ok, subneg(str)}
    end
  end

  @doc "Build the Core.Hello message sent at connection time."
  def core_hello do
    build_message("Core.Hello", %{
      name:    "ElixirMUD",
      version: "0.1.0"
    })
  end

  # ─── Receiving ────────────────────────────────────────────────────────────

  @doc """
  Dispatch a received GMCP subnegotiation payload.
  Returns `{new_gmcp_state, action}` where action is one of:
    `:ok`
    `{:send, iodata}`     — caller should send these bytes to client
    `{:event, event}`     — caller should forward to session/world
  """
  @spec handle_subneg(state(), binary()) :: {state(), term()}
  def handle_subneg(state, payload) do
    case parse_payload(payload) do
      {:ok, package, data} ->
        handle_package(state, package, data)

      {:error, reason} ->
        Logger.debug("GMCP parse error: #{inspect(reason)}")
        {state, :ok}
    end
  end

  # ─── Package handlers (add your own here) ─────────────────────────────────

  # Client telling us which packages it supports
  defp handle_package(state, "Core.Supports.Set", list) when is_list(list) do
    Logger.debug("GMCP Core.Supports.Set: #{inspect(list)}")
    {%{state | client_supports: list}, :ok}
  end

  defp handle_package(state, "Core.Supports.Add", list) when is_list(list) do
    new_list = Enum.uniq(state.client_supports ++ list)
    {%{state | client_supports: new_list}, :ok}
  end

  defp handle_package(state, "Core.Supports.Remove", list) when is_list(list) do
    new_list = state.client_supports -- list
    {%{state | client_supports: new_list}, :ok}
  end

  defp handle_package(state, "Core.Ping", _data) do
    {:ok, pong} = build_message("Core.Ping")
    {state, {:send, pong}}
  end

  # Hook for future Char.* packages
  defp handle_package(state, "Char." <> _ = pkg, data) do
    {state, {:event, {:gmcp, pkg, data}}}
  end

  # Hook for Room.* packages
  defp handle_package(state, "Room." <> _ = pkg, data) do
    {state, {:event, {:gmcp, pkg, data}}}
  end

  # Catch-all — surface as a generic event so game code can react
  defp handle_package(state, package, data) do
    Logger.debug("Unhandled GMCP package: #{package}")
    {state, {:event, {:gmcp, package, data}}}
  end

  # ─── Private helpers ──────────────────────────────────────────────────────

  defp parse_payload(payload) do
    # payload = "Package.Name" or "Package.Name {...json...}"
    case :binary.split(payload, " ", [:global]) do
      [package] ->
        {:ok, package, nil}

      [package | rest] ->
        json = Enum.join(rest, " ")
        case Jason.decode(json) do
          {:ok, data}      -> {:ok, package, data}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end
    end
  end

  defp subneg(payload) do
    iac  = 255
    sb   = 250
    se   = 240
    gmcp = 201
    <<iac::8, sb::8, gmcp::8, payload::binary, iac::8, se::8>>
  end

  defp return_error(err), do: err
end
