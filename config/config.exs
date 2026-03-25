import Config

config :elixir_mud,
  # Telnet listener port
  port: 4000,
  # Maximum simultaneous connections (ranch acceptor pool size)
  max_connections: 1000,
  # Idle timeout in ms before a connection is dropped (0 = disabled)
  idle_timeout: 300_000,
  # Welcome banner sent immediately on connect
  welcome_banner: "Welcome to ElixirMUD\n\n"

import_config "#{config_env()}.exs"
