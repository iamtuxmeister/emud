defmodule Emud.Session do
  @moduledoc """
  Player session process — sits between the raw TCP connection and the
  game world.  One `Session` process exists per connected player.

  Responsibilities
  ----------------
  - Hold the player's in-game state (character, room, stats)
  - Route raw input lines through `Emud.Command.dispatch/2`
  - Route output from the world back to the connection
  - Handle GMCP / MSDP events forwarded by the connection

  Registration
  ------------
  Sessions register under the player name in `Emud.Session.Registry`:

      Registry.lookup(Emud.Session.Registry, "Alice")

  Usage
  -----
  Start from the connection process after login:

      {:ok, pid} = Emud.Session.start_link(conn_pid: self(), name: "Alice")

  The connection sends raw input as:

      send(session_pid, {:input, line})
  """

  use GenServer
  require Logger

  alias Emud.Telnet.Connection
  alias Emud.Command

  defstruct [
    :conn_pid,
    :player_name,
    :room_id,
    :character
  ]

  # --- API ------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Send text output to this session's connection."
  def send_output(pid, text), do: GenServer.cast(pid, {:output, text})

  # --- GenServer callbacks --------------------------------------------------

  @impl GenServer
  def init(opts) do
    conn_pid    = Keyword.fetch!(opts, :conn_pid)
    player_name = Keyword.get(opts, :name, "Anonymous")

    Registry.register(Emud.Session.Registry, player_name, self())

    state = %__MODULE__{
      conn_pid:    conn_pid,
      player_name: player_name,
      room_id:     :limbo,
      character:   %{hp: 100, max_hp: 100, mp: 100, max_mp: 100}
    }

    Logger.info("Session started for #{player_name}")
    {:ok, state}
  end

  # Raw input line from the TCP connection
  @impl GenServer
  def handle_info({:input, line}, state) do
    state = Command.dispatch(state, String.trim(line))
    {:noreply, state}
  end

  # GMCP event forwarded by the connection
  def handle_info({:gmcp, package, data}, state) do
    Logger.debug("GMCP #{package}: #{inspect(data)}")
    {:noreply, state}
  end

  # MSDP event forwarded by the connection
  def handle_info({:msdp, var, value}, state) do
    Logger.debug("MSDP #{var}=#{inspect(value)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:output, text}, state) do
    Connection.send_text(state.conn_pid, text)
    {:noreply, state}
  end
end
