defmodule Emud.Telnet.GMCP do
  @moduledoc """
  GMCP — Generic MUD Communication Protocol  (option 201).

  Messages are sent inside telnet subnegotiation as:
      "Package.Name" <SPACE> {"json":"data"}

  Adding a new package
  --------------------
  1. Add a `handle_package/3` clause below.
  2. Call `GMCP.send_package/3` from connection or game logic.
  """

  require Logger

  @type state :: %{enabled: boolean(), client_supports: list(String.t())}

  def new, do: %{enabled: false, client_supports: []}
  def enable(state), do: %{state | enabled: true}

  # ─── Sending ──────────────────────────────────────────────────────────────

  @doc "Build a GMCP subneg frame. `data` is any Jason-encodable term or nil."
  @spec build_message(String.t(), term()) :: {:ok, iodata()} | {:error, term()}
  def build_message(package, data \\ nil) do
    payload =
      if is_nil(data) do
        {:ok, package}
      else
        case Jason.encode(data) do
          {:ok, json}      -> {:ok, "#{package} #{json}"}
          {:error, _} = e  -> e
        end
      end

    case payload do
      {:ok, str}       -> {:ok, subneg(str)}
      {:error, _} = e  -> e
    end
  end

  @doc "Core.Hello message sent at connection time."
  def core_hello do
    build_message("Core.Hello", %{name: "EMUD", version: "0.1.0"})
  end

  # ─── Receiving ────────────────────────────────────────────────────────────

  @doc """
  Dispatch a received GMCP subneg payload.
  Returns `{new_state, action}` where action is:
    `:ok` | `{:send, iodata}` | `{:event, event}`
  """
  @spec handle_subneg(state(), binary()) :: {state(), term()}
  def handle_subneg(state, payload) do
    case parse_payload(payload) do
      {:ok, package, data} -> handle_package(state, package, data)
      {:error, reason}     ->
        Logger.debug("GMCP parse error: #{inspect(reason)}")
        {state, :ok}
    end
  end

  # ─── Package handlers ─────────────────────────────────────────────────────

  defp handle_package(state, "Core.Supports.Set", list) when is_list(list) do
    {%{state | client_supports: list}, :ok}
  end

  defp handle_package(state, "Core.Supports.Add", list) when is_list(list) do
    {%{state | client_supports: Enum.uniq(state.client_supports ++ list)}, :ok}
  end

  defp handle_package(state, "Core.Supports.Remove", list) when is_list(list) do
    {%{state | client_supports: state.client_supports -- list}, :ok}
  end

  defp handle_package(state, "Core.Ping", _data) do
    {:ok, pong} = build_message("Core.Ping")
    {state, {:send, pong}}
  end

  defp handle_package(state, pkg, data) do
    Logger.debug("GMCP: #{pkg}")
    {state, {:event, {:gmcp, pkg, data}}}
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp parse_payload(payload) do
    case :binary.split(payload, " ", [:global]) do
      [package]      -> {:ok, package, nil}
      [package | rest] ->
        json = Enum.join(rest, " ")
        case Jason.decode(json) do
          {:ok, data}      -> {:ok, package, data}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end
    end
  end

  defp subneg(payload) do
    <<255::8, 250::8, 201::8, payload::binary, 255::8, 240::8>>
  end
end
