defmodule ElixirMud do
  @moduledoc """
  ElixirMUD — an OTP-based MUD server.

  Quick-start
  -----------
      mix deps.get
      iex -S mix

  Then connect with any telnet client:
      telnet localhost 4000

  Or use a MUD client that supports GMCP/MSDP/MCCP2 (MUSHclient, Mudlet,
  tintin++, etc.) pointed at localhost:4000.

  Architecture overview
  ---------------------
      Application (Supervisor)
      ├── Session.Registry        — ETS-backed Registry of live sessions
      └── :ranch listener         — TCP acceptor pool
          └── Connection (×N)     — one GenServer per TCP connection
              ├── Telnet.Protocol — pure-functional byte-stream parser
              ├── MCCP2           — zlib compression state
              ├── GMCP            — JSON sub-protocol state
              └── MSDP            — key-value sub-protocol state

  Each `Connection` optionally spawns a `Session` after login.
  """
end
