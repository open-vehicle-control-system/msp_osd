defmodule MspOsd.Crc do
  @moduledoc """
  CRC primitives used by MSP framing.

  - `xor8/1` — MSPv1 checksum (XOR of all bytes in the CRC region).
  - `dvb_s2/1` — MSPv2 checksum (CRC-8/DVB-S2, poly 0xD5, init 0x00).
  """

  import Bitwise

  @spec xor8(binary()) :: byte()
  def xor8(bytes) when is_binary(bytes) do
    xor8(bytes, 0)
  end

  defp xor8(<<>>, acc), do: acc
  defp xor8(<<byte, rest::binary>>, acc), do: xor8(rest, bxor(acc, byte))

  @spec dvb_s2(binary()) :: byte()
  def dvb_s2(bytes) when is_binary(bytes) do
    dvb_s2_bytes(bytes, 0)
  end

  defp dvb_s2_bytes(<<>>, crc), do: crc

  defp dvb_s2_bytes(<<byte, rest::binary>>, crc) do
    dvb_s2_bytes(rest, dvb_s2_byte(bxor(crc, byte), 8))
  end

  defp dvb_s2_byte(crc, 0), do: crc &&& 0xFF

  defp dvb_s2_byte(crc, n) do
    next =
      if (crc &&& 0x80) != 0 do
        bxor(bsl(crc, 1), 0xD5)
      else
        bsl(crc, 1)
      end

    dvb_s2_byte(next &&& 0xFF, n - 1)
  end
end
