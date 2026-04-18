defmodule MspOsd.CrcTest do
  use ExUnit.Case, async: true

  alias MspOsd.Crc

  describe "xor8/1" do
    test "empty input is 0" do
      assert Crc.xor8(<<>>) == 0
    end

    test "single byte is itself" do
      assert Crc.xor8(<<0x5A>>) == 0x5A
    end

    test "xor of a run of bytes" do
      assert Crc.xor8(<<1, 2, 3>>) == 0 |> Bitwise.bxor(1) |> Bitwise.bxor(2) |> Bitwise.bxor(3)
    end

    test "xor of a byte with itself is 0" do
      assert Crc.xor8(<<0xAA, 0xAA>>) == 0
    end
  end

  describe "dvb_s2/1" do
    test "empty input is 0" do
      assert Crc.dvb_s2(<<>>) == 0
    end

    test "0x00 -> 0x00" do
      assert Crc.dvb_s2(<<0x00>>) == 0x00
    end

    test "0x01 -> 0xD5 (poly shift without feedback)" do
      assert Crc.dvb_s2(<<0x01>>) == 0xD5
    end

    test "result is always a byte" do
      for bytes <- [<<0xFF, 0xFF, 0xFF>>, <<0xA5, 0x5A>>, <<1, 2, 3, 4, 5, 6>>] do
        crc = Crc.dvb_s2(bytes)
        assert crc in 0..0xFF
      end
    end
  end
end
