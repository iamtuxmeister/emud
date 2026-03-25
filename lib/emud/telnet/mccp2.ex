defmodule Emud.Telnet.MCCP2 do
  @moduledoc """
  MCCP v2 — Mud Client Compression Protocol v2  (option 86).

  After the server sends `IAC WILL MCCP2` and receives `IAC DO MCCP2`,
  it sends `IAC SB MCCP2 IAC SE` to signal that all subsequent bytes
  will be compressed with zlib DEFLATE (windowBits = 15).

  Lifecycle
  ---------
    1. Connection advertises: `will(opt_mccp2())`
    2. Client acknowledges:   receives `{:do, opt_mccp2()}`
    3. Call `enable/1`        → returns SB handshake + opens zlib stream
    4. All subsequent sends go through `compress/2`
    5. On disconnect call `disable/1` to close the zlib stream
  """

  require Emud.Telnet.Options, as: O

  defstruct enabled: false,
            zstream: nil

  @type t :: %__MODULE__{}

  def new, do: %__MODULE__{}

  @doc """
  Enable MCCP2. Returns `{new_state, handshake_bytes}`.
  The handshake bytes MUST be sent uncompressed as the last uncompressed write.
  """
  @spec enable(t()) :: {t(), binary()}
  def enable(%__MODULE__{enabled: false} = state) do
    z = :zlib.open()
    :zlib.deflateInit(z, :default, :deflated, 15, 8, :default)
    handshake = O.subneg(86, <<>>)   # 86 = opt_mccp2
    {%{state | enabled: true, zstream: z}, handshake}
  end

  def enable(%__MODULE__{enabled: true} = state), do: {state, <<>>}

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

  @doc "Compress `data` if enabled; pass through unchanged if not."
  @spec compress(t(), binary()) :: binary()
  def compress(%__MODULE__{enabled: true, zstream: z}, data) do
    z |> :zlib.deflate(data, :sync) |> IO.iodata_to_binary()
  end

  def compress(_state, data), do: data
end
