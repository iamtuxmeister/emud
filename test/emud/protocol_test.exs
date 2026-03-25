defmodule Emud.Telnet.ProtocolTest do
  use ExUnit.Case, async: true

  alias Emud.Telnet.Protocol
  require Emud.Telnet.Options, as: O

  test "plain text is returned as :data event" do
    {_state, events} = Protocol.feed(Protocol.new(), "hello\r\n")
    assert [{:data, "hello\r\n"}] = events
  end

  test "WILL GMCP produces a :will event" do
    bytes = <<O.iac()::8, O.will()::8, O.opt_gmcp()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:will, O.opt_gmcp()}] = events
  end

  test "DO MCCP2 produces a :do event" do
    bytes = <<O.iac()::8, O.do_()::8, O.opt_mccp2()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:do, O.opt_mccp2()}] = events
  end

  test "subnegotiation is reassembled" do
    inner = "Core.Hello {}"
    bytes = <<O.iac()::8, O.sb()::8, O.opt_gmcp()::8>> <>
            inner <>
            <<O.iac()::8, O.se()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:subneg, O.opt_gmcp(), ^inner}] = events
  end

  test "escaped IAC (0xFF 0xFF) in data stream" do
    bytes = <<O.iac()::8, O.iac()::8>>
    {_state, events} = Protocol.feed(Protocol.new(), bytes)
    assert [{:data, <<255>>}] = events
  end

  test "mixed telnet and plain text" do
    will_gmcp = <<O.iac()::8, O.will()::8, O.opt_gmcp()::8>>
    input = "look" <> will_gmcp <> "\r\n"
    {_state, events} = Protocol.feed(Protocol.new(), input)
    data_events = for {:data, t} <- events, do: t
    assert Enum.any?(data_events, &String.contains?(&1, "look"))
    assert Enum.any?(events, &match?({:will, O.opt_gmcp()}, &1))
  end

  test "parser maintains state across partial inputs" do
    {state1, events1} = Protocol.feed(Protocol.new(), <<O.iac()::8>>)
    assert events1 == []
    {_state2, events2} = Protocol.feed(state1, <<O.will()::8, O.opt_gmcp()::8>>)
    assert [{:will, O.opt_gmcp()}] = events2
  end
end
