import Config

config :emud,
  port:            4000,
  max_connections: 1000,
  idle_timeout:    300_000,
  welcome_banner:  "Welcome to EMUD\n\n"

import_config "#{config_env()}.exs"
