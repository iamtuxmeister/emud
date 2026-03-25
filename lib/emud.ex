defmodule Emud do
  @moduledoc """
  EMUD — an OTP-based MUD server.

  Quick-start
  -----------
      mix deps.get
      iex -S mix

  Connect with any telnet client:
      telnet localhost 4000

  Architecture overview
  ---------------------
      Application (Supervisor)
      ├── Session.Registry        — ETS-backed Registry of live sessions
      └── :ranch listener         — TCP acceptor pool
          └── Telnet.Connection   — one GenServer per TCP connection
              ├── Telnet.Protocol — pure-functional byte-stream parser
              ├── Telnet.MCCP2    — zlib compression state
              ├── Telnet.GMCP     — JSON sub-protocol state
              └── Telnet.MSDP     — key-value sub-protocol state
  """
end
