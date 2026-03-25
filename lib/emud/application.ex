defmodule Emud.Application do
  @moduledoc """
  OTP Application entry point for EMUD.

  Supervision tree:
    Emud.Application (Supervisor)
    ├── Emud.Session.Registry  (Registry for player sessions)
    └── :ranch listener        (managed by Ranch itself)
        └── Telnet.Connection  (one GenServer per TCP connection)

  Ranch 2.x note: TCP-level options go in socket_opts. Ranch manages
  reuseaddr/nodelay/keepalive itself — do not pass them explicitly.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port    = Application.get_env(:emud, :port, 4000)
    max_con = Application.get_env(:emud, :max_connections, 1000)

    children = [
      {Registry, keys: :unique, name: Emud.Session.Registry},

      :ranch.child_spec(
        :telnet_listener,
        :ranch_tcp,
        %{
          num_acceptors:   10,
          max_connections: max_con,
          socket_opts:     [port: port]
        },
        Emud.Telnet.Connection,
        []
      )
    ]

    opts = [strategy: :one_for_one, name: Emud.Supervisor]
    Logger.info("EMUD starting on port #{port}")
    Supervisor.start_link(children, opts)
  end
end
