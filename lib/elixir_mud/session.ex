defmodule ElixirMud.Session do
  @moduledoc """
  Player session process — sits between the raw TCP connection and the
  game world.  One `Session` process exists per connected player.

  Responsibilities (stubs — flesh out as the game grows)
  -------------------------------------------------------
  - Authenticate the player (login flow)
  - Hold the player's in-game state (character, room, stats)
  - Route input lines to the command parser
  - Route output from the world back to the connection

  Registration
  ------------
  When a session is started it registers itself under the player's name
  in `ElixirMud.Session.Registry` so other processes can find it:

      Registry.lookup(ElixirMud.Session.Registry, "Alice")

  Usage
  -----
  Sessions are started by the connection after login:

      {:ok, pid} = Session.start_link(conn_pid: self(), name: "Alice")

  The connection forwards raw input lines as:

      send(session_pid, {:input, line})

  The session calls back:

      Connection.send_text(conn_pid, "You stand in the void.")
  """

  use GenServer
  require Logger
  alias ElixirMud.Telnet.Connection

  defstruct [
    :conn_pid,
    :player_name,
    :room_id,     # placeholder
    :character    # placeholder map
  ]

  # ─── API ──────────────────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_output(pid, text), do: GenServer.cast(pid, {:output, text})

  # ─── GenServer callbacks ──────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    conn_pid    = Keyword.fetch!(opts, :conn_pid)
    player_name = Keyword.get(opts, :name, "Anonymous")

    # Register so others can look us up
    Registry.register(ElixirMud.Session.Registry, player_name, self())

    state = %__MODULE__{
      conn_pid:    conn_pid,
      player_name: player_name,
      room_id:     :limbo,
      character:   %{hp: 100, max_hp: 100, mp: 100, max_mp: 100}
    }

    Logger.info("Session started for #{player_name}")
    {:ok, state}
  end

  # Input from the TCP connection
  @impl GenServer
  def handle_info({:input, line}, state) do
    line = String.trim(line)
    state = dispatch_command(state, line)
    {:noreply, state}
  end

  # GMCP event forwarded by the connection
  def handle_info({:gmcp, package, data}, state) do
    Logger.debug("Session received GMCP #{package}: #{inspect(data)}")
    {:noreply, state}
  end

  # MSDP event forwarded by the connection
  def handle_info({:msdp, var, value}, state) do
    Logger.debug("Session received MSDP #{var}=#{inspect(value)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:output, text}, state) do
    Connection.send_text(state.conn_pid, text)
    {:noreply, state}
  end

  # ─── Command dispatcher (stub) ────────────────────────────────────────────

  defp dispatch_command(state, "") do
    Connection.send_text(state.conn_pid, "\r\n")
    state
  end

  defp dispatch_command(state, "look") do
    Connection.send_text(state.conn_pid, room_description(state.room_id))
    state
  end

  defp dispatch_command(state, "quit") do
    Connection.send_text(state.conn_pid, "Goodbye!\r\n")
    # TODO: trigger connection close from connection side
    state
  end

  defp dispatch_command(state, cmd) do
    Connection.send_text(state.conn_pid, "Unknown command: #{cmd}\r\n")
    state
  end

  # ─── Placeholder world data ───────────────────────────────────────────────

  defp room_description(:limbo) do
    """
    [ The Void ]
    An infinite grey expanse stretches in every direction.
    There are no exits.

    """
  end

  defp room_description(_), do: "You are somewhere.\r\n"
end
