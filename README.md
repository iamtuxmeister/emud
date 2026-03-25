# EMUD

An OTP-based MUD server written in Elixir with full support for modern
telnet extensions: **MCCP2**, **GMCP**, and **MSDP**.

## Requirements

- Elixir ~> 1.15
- Erlang/OTP 26+

## Quick start

```bash
mix deps.get
iex -S mix
```

Connect on **port 4000**:

```bash
telnet localhost 4000
```

## Protocol support

| Protocol    | Option | Status | Notes                        |
|-------------|--------|--------|------------------------------|
| Telnet      | RFC 854 | ✅    | Full IAC/SB/SE parsing       |
| NAWS        | 31     | ✅    | Window-size reporting        |
| TTYPE       | 24     | ✅    | Terminal-type detection      |
| Suppress GA | 3      | ✅    | Negotiated on connect        |
| MSDP        | 69     | ✅    | Key-value data protocol      |
| MCCP2       | 86     | ✅    | zlib DEFLATE compression     |
| GMCP        | 201    | ✅    | JSON sub-protocol            |
| MCCP1       | 85     | ❌    | Obsolete, not implemented    |

## Project layout

```
lib/
  emud.ex                      Top-level module & docs
  emud/
    application.ex             OTP Application + supervision tree
    session.ex                 Per-player session GenServer (stub)
    telnet/
      connection.ex            Ranch protocol handler (per-connection GenServer)
      protocol.ex              Pure-functional IAC stream parser
      options.ex               Telnet byte constants & builder helpers
      mccp2.ex                 MCCP2 compression state machine
      gmcp.ex                  GMCP JSON sub-protocol
      msdp.ex                  MSDP key-value sub-protocol
```

## Adding a GMCP package

1. Add a `handle_package/3` clause in `Emud.Telnet.GMCP`:

```elixir
defp handle_package(state, "Char.Vitals", data) do
  {state, {:event, {:vitals, data}}}
end
```

2. Handle the event in `Emud.Session`:

```elixir
def handle_info({:gmcp, "Char.Vitals", data}, state) do
  {:noreply, state}
end
```

## Configuration

`config/config.exs`:

```elixir
config :emud,
  port:            4000,
  max_connections: 1000,
  idle_timeout:    300_000,
  welcome_banner:  "Welcome to EMUD\n\n"
```
