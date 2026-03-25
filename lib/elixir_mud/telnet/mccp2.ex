defmodule ElixirMud.Telnet.MCCP2 do
  @moduledoc """
  MCCP v2 — Mud Client Compression Protocol v2  (option 86).

  After the server sends `IAC WILL MCCP2` and receives `IAC DO MCCP2`,
  it must send `IAC SB MCCP2 IAC SE` to signal that all subsequent bytes
  will be compressed with zlib DEFLATE (raw, windowBits = 15).

  This module tracks per-connection compression state.

  Lifecycle
  ---------
    1. Connection advertises: send `will(opt_mccp2())`
    2. Client acknowledges:   receives `{:do, opt_mccp2()}`
    3. Call `enable/1` → returns the SB handshake + a zlib stream ref
    4. All subsequent sends go through `compress/2`
    5. On disconnect call `disable/1` to close the zlib stream

  ## Note on MCCP1
  MCCP1 (option 85) is obsolete and should never be advertised.
  Clients that send `{:do, 85}` should receive `WONT MCCP1` in reply.
  """

  alias ElixirMud.Telnet.Options, as: O

  defstruct enabled: false,
            zstream: nil

  @type t :: %__MODULE__{}

  @doc "New (disabled) MCCP2 state."
  def new, do: %__MODULE__{}

  @doc """
  Enable MCCP2 compression.

  Returns `{new_state, handshake_bytes}` where `handshake_bytes` must be
  sent to the client **uncompressed** as the very last uncompressed bytes.
  All bytes sent after this point MUST be compressed.
  """
  @spec enable(t()) :: {t(), binary()}
  def enable(%__MODULE__{enabled: false} = state) do
    z = :zlib.open()
    :zlib.deflateInit(z, :default, :deflated, 15, 8, :default)
    handshake = O.subneg(O.opt_mccp2(), <<>>)
    {%{state | enabled: true, zstream: z}, handshake}
  end

  def enable(%__MODULE__{enabled: true} = state) do
    # Already enabled — return empty handshake
    {state, <<>>}
  end

  @doc "Disable MCCP2 and clean up the zlib stream."
  @spec disable(t()) :: t()
  def disable(%__MODULE__{enabled: true, zstream: z} = state) do
    try do
      :zlib.deflateEnd(z)
      :zlib.close(z)
    rescue
      _ -> :ok
    end
    %{state | enabled: false, zstream: nil}
  end

  def disable(state), do: state

  @doc """
  Compress `data` if MCCP2 is enabled; pass through unchanged if not.
  Uses `sync` flush so the client can decompress each chunk immediately.
  """
  @spec compress(t(), binary()) :: binary()
  def compress(%__MODULE__{enabled: true, zstream: z}, data) do
    z
    |> :zlib.deflate(data, :sync)
    |> IO.iodata_to_binary()
  end

  def compress(_state, data), do: data
end
