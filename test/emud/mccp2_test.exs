defmodule Emud.Telnet.MCCP2Test do
  use ExUnit.Case, async: true

  alias Emud.Telnet.MCCP2

  test "compress is identity when disabled" do
    assert MCCP2.compress(MCCP2.new(), "hello") == "hello"
  end

  test "enable returns handshake bytes" do
    {state, handshake} = MCCP2.enable(MCCP2.new())
    assert state.enabled == true
    assert byte_size(handshake) > 0
  end

  test "compress reduces size when enabled" do
    {state, _} = MCCP2.enable(MCCP2.new())
    plain = String.duplicate("A", 100)
    assert byte_size(MCCP2.compress(state, plain)) < byte_size(plain)
  end

  test "disable cleans up without error" do
    {state, _} = MCCP2.enable(MCCP2.new())
    assert %MCCP2{enabled: false} = MCCP2.disable(state)
  end
end
