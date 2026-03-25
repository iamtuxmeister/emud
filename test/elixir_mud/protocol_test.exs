defmodule ElixirMud.Telnet.ProtocolTest do
  use ExUnit.Case, async: true

  alias ElixirMud.Telnet.{Protocol, Options}

  test "plain text is returned as :data event" do
    {_state, events} = Protocol.feed(Protocol.new(), "hello\r\n")
    assert [{:data, "hello\r\n"}] = events
  end

  test "WILL GMCP produces a :will event" do
    bytes = <<Options.iac()::8, Options.will()::8, Options.opt_gmcp()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:will, Options.opt_gmcp()}] = events
  end

  test "DO MCCP2 produces a :do event" do
    bytes = <<Options.iac()::8, Options.do_()::8, Options.opt_mccp2()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:do, Options.opt_mccp2()}] = events
  end

  test "subnegotiation is reassembled across multiple bytes" do
    inner = "Core.Hello {}"
    iac = Options.iac()
    sb  = Options.sb()
    se  = Options.se()
    opt = Options.opt_gmcp()
    bytes = <<iac::8, sb::8, opt::8>> <> inner <> <<iac::8, se::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:subneg, ^opt, ^inner}] = events
  end

  test "escaped IAC (0xFF 0xFF) in data stream" do
    bytes = <<Options.iac()::8, Options.iac()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:data, <<255>>}] = events
  end

  test "mixed telnet and plain text" do
    will_gmcp = <<Options.iac()::8, Options.will()::8, Options.opt_gmcp()::8>>
    input = "look" <> will_gmcp <> "\r\n"
    {_state, events} = Protocol.feed(Protocol.new(), input)
    data_events = for {:data, t} <- events, do: t
    assert Enum.any?(data_events, &String.contains?(&1, "look"))
    assert Enum.any?(events, &match?({:will, Options.opt_gmcp()}, &1))
  end

  test "parser maintains state across partial inputs" do
    iac = <<Options.iac()::8>>
    rest = <<Options.will()::8, Options.opt_gmcp()::8>>
    {state1, events1} = Protocol.feed(Protocol.new(), iac)
    assert events1 == []
    {_state2, events2} = Protocol.feed(state1, rest)
    assert [{:will, Options.opt_gmcp()}] = events2
  end
end
