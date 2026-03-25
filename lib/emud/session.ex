defmodule Emud.Session do
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
  Sessions register under the player name in `Emud.Session.Registry`:

      Registry.lookup(Emud.Session.Registry, "Alice")

  Usage
  -----
  Started by the connection after login:

      {:ok, pid} = Emud.Session.start_link(conn_pid: self(), name: "Alice")

  The connection forwards input lines as:

      send(session_pid, {:input, line})
  """

  use GenServer
  require Logger
  alias Emud.Telnet.Connection

  defstruct [
    :conn_pid,
    :player_name,
    :room_id,
    :character
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

  @impl GenServer
  def handle_info({:input, line}, state) do
    state = dispatch_command(state, String.trim(line))
    {:noreply, state}
  end

  def handle_info({:gmcp, package, data}, state) do
    Logger.debug("GMCP #{package}: #{inspect(data)}")
    {:noreply, state}
  end

  def handle_info({:msdp, var, value}, state) do
    Logger.debug("MSDP #{var}=#{inspect(value)}")
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
    state
  end

  defp dispatch_command(state, cmd) do
    Connection.send_text(state.conn_pid, "Unknown command: #{cmd}\r\n")
    state
  end

  # ─── Placeholder world data ───────────────────────────────────────────────

  defp room_description(:limbo) do
    "[ The Void ]\r\nAn infinite grey expanse stretches in every direction.\r\nThere are no exits.\r\n\r\n"
  end

  defp room_description(_), do: "You are somewhere.\r\n"
end
