defmodule ElixirMud.Telnet.MCCP2Test do
  use ExUnit.Case, async: true

  alias ElixirMud.Telnet.MCCP2

  test "compress is identity when disabled" do
    state = MCCP2.new()
    assert MCCP2.compress(state, "hello") == "hello"
  end

  test "enable returns handshake bytes" do
    {state, handshake} = MCCP2.enable(MCCP2.new())
    assert state.enabled == true
    assert byte_size(handshake) > 0
  end

  test "compress produces different bytes when enabled" do
    {state, _} = MCCP2.enable(MCCP2.new())
    plain = String.duplicate("A", 100)
    compressed = MCCP2.compress(state, plain)
    # zlib should reduce 100 identical bytes considerably
    assert byte_size(compressed) < byte_size(plain)
  end

  test "disable cleans up without error" do
    {state, _} = MCCP2.enable(MCCP2.new())
    assert %MCCP2{enabled: false} = MCCP2.disable(state)
  end
end
