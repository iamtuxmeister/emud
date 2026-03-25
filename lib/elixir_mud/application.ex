defmodule ElixirMud.Application do
  @moduledoc """
  OTP Application entry point for ElixirMUD.

  Supervision tree:
    ElixirMud.Application (Supervisor)
    ├── :ranch listener  (managed by Ranch itself)
    └── ElixirMud.Session.Registry  (Registry for player sessions)

  Ranch spawns a new ElixirMud.Telnet.Connection process for every
  TCP connection, supervised by Ranch's own acceptor pool supervisor.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port    = Application.get_env(:elixir_mud, :port, 4000)
    max_con = Application.get_env(:elixir_mud, :max_connections, 1000)

    children = [
      # Registry used to look up sessions by player name / PID
      {Registry, keys: :unique, name: ElixirMud.Session.Registry},

      # Ranch listener — spins up the TCP acceptor pool.
      # Each accepted connection is handled by ElixirMud.Telnet.Connection.
      :ranch.child_spec(
        :telnet_listener,
        :ranch_tcp,
        %{
          port: port,
          max_connections: max_con,
          num_acceptors: 10
        },
        ElixirMud.Telnet.Connection,
        []   # <-- protocol options passed to Connection.init/1
      )
    ]

    opts = [strategy: :one_for_one, name: ElixirMud.Supervisor]
    Logger.info("ElixirMUD starting on port #{port}")
    Supervisor.start_link(children, opts)
  end
end
