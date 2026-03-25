defmodule Emud.Telnet.Protocol do
  @moduledoc """
  Pure-functional Telnet byte-stream parser.

  ## Usage

      state = Protocol.new()
      {state, events} = Protocol.feed(state, raw_bytes)

  Events returned:
    `{:data, binary}`       — plain text meant for the game
    `{:will, opt}`          — client says it WILL support <opt>
    `{:wont, opt}`          — client says it WONT support <opt>
    `{:do, opt}`            — client requests server DO <opt>
    `{:dont, opt}`          — client requests server DONT <opt>
    `{:subneg, opt, binary}` — subnegotiation payload for <opt>
  """

  require Emud.Telnet.Options, as: O

  defstruct state: :data,
            buf:    <<>>,
            sb_opt: nil,
            sb_buf: <<>>

  @type t :: %__MODULE__{}

  @doc "Create a new parser state."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Feed raw bytes into the parser. Returns `{new_state, [event]}`."
  @spec feed(t(), binary()) :: {t(), list()}
  def feed(state, data) when is_binary(data) do
    {state, events_rev} = parse(state, data, [])
    {state, events_rev} = flush_buf(state, events_rev)
    {state, Enum.reverse(events_rev)}
  end

  # ─── Internal parser ──────────────────────────────────────────────────────

  defp parse(state, <<>>, acc), do: {state, acc}

  # :data mode
  defp parse(%{state: :data} = s, <<O.iac()::8, rest::binary>>, acc) do
    {s, acc} = flush_buf(s, acc)
    parse(%{s | state: :iac}, rest, acc)
  end

  defp parse(%{state: :data} = s, <<byte::8, rest::binary>>, acc) do
    parse(%{s | buf: <<s.buf::binary, byte::8>>}, rest, acc)
  end

  # :iac mode
  defp parse(%{state: :iac} = s, <<O.iac()::8, rest::binary>>, acc) do
    parse(%{s | state: :data, buf: <<s.buf::binary, 255::8>>}, rest, acc)
  end

  defp parse(%{state: :iac} = s, <<O.sb()::8, rest::binary>>, acc) do
    parse(%{s | state: :sb_opt}, rest, acc)
  end

  defp parse(%{state: :iac} = s, <<cmd::8, rest::binary>>, acc)
       when cmd in [O.will(), O.wont(), O.do_(), O.dont()] do
    parse(%{s | state: {:option, cmd}}, rest, acc)
  end

  defp parse(%{state: :iac} = s, <<_cmd::8, rest::binary>>, acc) do
    parse(%{s | state: :data}, rest, acc)
  end

  # option negotiation
  defp parse(%{state: {:option, cmd}} = s, <<opt::8, rest::binary>>, acc) do
    parse(%{s | state: :data}, rest, [option_event(cmd, opt) | acc])
  end

  # subnegotiation: first byte is the option code
  defp parse(%{state: :sb_opt} = s, <<opt::8, rest::binary>>, acc) do
    parse(%{s | state: :sb_data, sb_opt: opt, sb_buf: <<>>}, rest, acc)
  end

  # IAC SE closes the subneg
  defp parse(%{state: :sb_data} = s, <<O.iac()::8, O.se()::8, rest::binary>>, acc) do
    parse(%{s | state: :data, sb_opt: nil, sb_buf: <<>>}, rest,
          [{:subneg, s.sb_opt, s.sb_buf} | acc])
  end

  # IAC IAC inside subneg = escaped 0xFF
  defp parse(%{state: :sb_data} = s, <<O.iac()::8, O.iac()::8, rest::binary>>, acc) do
    parse(%{s | sb_buf: <<s.sb_buf::binary, 255::8>>}, rest, acc)
  end

  defp parse(%{state: :sb_data} = s, <<O.iac()::8, _::8, rest::binary>>, acc) do
    parse(s, rest, acc)
  end

  defp parse(%{state: :sb_data} = s, <<byte::8, rest::binary>>, acc) do
    parse(%{s | sb_buf: <<s.sb_buf::binary, byte::8>>}, rest, acc)
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp flush_buf(%{buf: <<>>} = s, acc), do: {s, acc}
  defp flush_buf(s, acc), do: {%{s | buf: <<>>}, [{:data, s.buf} | acc]}

  defp option_event(O.will(), opt), do: {:will, opt}
  defp option_event(O.wont(), opt), do: {:wont, opt}
  defp option_event(O.do_(),  opt), do: {:do,   opt}
  defp option_event(O.dont(), opt), do: {:dont, opt}
end
