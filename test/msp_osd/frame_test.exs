defmodule MspOsd.FrameTest do
  use ExUnit.Case, async: true

  alias MspOsd.Frame

  describe "encode/1 v1" do
    test "short payload produces $M<dir><size><cmd><data><crc>" do
      frame = Frame.build(:v1, :response, 101, <<1, 2, 3>>)
      assert {:ok, bytes} = Frame.encode(frame)

      # $M + '>' + size=3 + cmd=101 + data=<<1,2,3>> + crc
      <<"$M", ?>, 3, 101, 1, 2, 3, crc>> = bytes
      assert crc == Bitwise.bxor(Bitwise.bxor(3, 101), Bitwise.bxor(Bitwise.bxor(1, 2), 3))
    end

    test "empty payload has size 0" do
      frame = Frame.build(:v1, :request, 10, <<>>)
      assert {:ok, <<"$M", ?<, 0, 10, crc>>} = Frame.encode(frame)
      assert crc == Bitwise.bxor(0, 10)
    end

    test "error direction encodes as '!'" do
      frame = Frame.build(:v1, :error, 3, <<>>)
      assert {:ok, <<"$M", ?!, 0, 3, _>>} = Frame.encode(frame)
    end

    test "rejects command > 0xFF" do
      frame = Frame.build(:v1, :request, 0x100, <<>>)
      assert {:error, :command_out_of_range_for_v1} = Frame.encode(frame)
    end

    test "payload exactly 254 bytes uses regular framing" do
      data = :binary.copy(<<0x5A>>, 254)
      frame = Frame.build(:v1, :response, 42, data)
      assert {:ok, <<"$M", ?>, 254, 42, ^data::binary-size(254), _crc>>} = Frame.encode(frame)
    end

    test "payload 255 bytes triggers jumbo framing (size byte = 0xFF + u16 size)" do
      data = :binary.copy(<<0xA5>>, 255)
      frame = Frame.build(:v1, :response, 42, data)

      assert {:ok, <<"$M", ?>, 0xFF, 42, 255::little-size(16), ^data::binary-size(255), _crc>>} =
               Frame.encode(frame)
    end

    test "large jumbo payload round-trips" do
      data = :binary.copy(<<0x3C>>, 1500)
      frame = Frame.build(:v1, :response, 7, data)
      assert {:ok, bytes} = Frame.encode(frame)
      assert {[decoded], <<>>} = Frame.parse(bytes)
      assert decoded.version == :v1
      assert decoded.command == 7
      assert decoded.data == data
    end

    test "rejects payload > 0xFFFF" do
      data = :binary.copy(<<0>>, 0x10000)
      frame = Frame.build(:v1, :response, 1, data)
      assert {:error, :payload_too_large} = Frame.encode(frame)
    end
  end

  describe "encode/1 v2" do
    test "produces $X<dir><flag><cmd:u16><size:u16><data><crc8>" do
      frame = Frame.build(:v2, :request, 0x1234, <<0xDE, 0xAD>>, flag: 0)
      assert {:ok, bytes} = Frame.encode(frame)

      <<"$X", ?<, 0, 0x34, 0x12, 2, 0, 0xDE, 0xAD, crc>> = bytes
      # CRC is dvb_s2 over the inner bytes (flag..data)
      assert crc == MspOsd.Crc.dvb_s2(<<0, 0x34, 0x12, 2, 0, 0xDE, 0xAD>>)
    end

    test "supports commands > 0xFF" do
      frame = Frame.build(:v2, :request, 0x5F5F, <<>>)
      assert {:ok, _} = Frame.encode(frame)
    end

    test "supports large payloads up to 0xFFFF" do
      data = :binary.copy(<<0xAA>>, 10_000)
      frame = Frame.build(:v2, :response, 0x1000, data)
      assert {:ok, _} = Frame.encode(frame)
    end
  end

  describe "encode/1 v2_over_v1" do
    test "wraps a v2 inner payload inside a v1 frame with outer cmd 0xFF" do
      frame = Frame.build(:v2_over_v1, :response, 0x0AA4, <<>>, flag: 0)
      assert {:ok, bytes} = Frame.encode(frame)

      <<"$M", ?>, outer_size, 0xFF, rest::binary>> = bytes
      # outer payload = v2 inner (5 bytes) + v2 crc (1 byte)
      assert outer_size == 6
      <<_inner::binary-size(6), _outer_crc>> = rest
    end
  end

  describe "parse/1 round-trips" do
    test "v1 frame" do
      frame = Frame.build(:v1, :response, 101, <<250, 3, 0, 0>>)
      {:ok, bytes} = Frame.encode(frame)
      assert {[decoded], <<>>} = Frame.parse(bytes)

      assert decoded == %Frame{
               version: :v1,
               direction: :response,
               flag: 0,
               command: 101,
               data: <<250, 3, 0, 0>>
             }
    end

    test "v1 jumbo frame" do
      data = :binary.copy(<<0x77>>, 500)
      frame = Frame.build(:v1, :request, 86, data)
      {:ok, bytes} = Frame.encode(frame)
      assert {[decoded], <<>>} = Frame.parse(bytes)
      assert decoded.version == :v1
      assert decoded.command == 86
      assert decoded.data == data
    end

    test "v2 native frame" do
      frame = Frame.build(:v2, :request, 0x0AA4, <<>>, flag: 0x42)
      {:ok, bytes} = Frame.encode(frame)
      assert {[decoded], <<>>} = Frame.parse(bytes)

      assert decoded == %Frame{
               version: :v2,
               direction: :request,
               flag: 0x42,
               command: 0x0AA4,
               data: <<>>
             }
    end

    test "v2_over_v1 frame unwraps back to v2_over_v1" do
      frame = Frame.build(:v2_over_v1, :response, 0x1234, <<0xDE, 0xAD, 0xBE, 0xEF>>, flag: 0)
      {:ok, bytes} = Frame.encode(frame)
      assert {[decoded], <<>>} = Frame.parse(bytes)
      assert decoded.version == :v2_over_v1
      assert decoded.command == 0x1234
      assert decoded.data == <<0xDE, 0xAD, 0xBE, 0xEF>>
    end

    test "multiple frames in one buffer" do
      {:ok, b1} = Frame.encode(Frame.build(:v1, :response, 2, "INAV"))
      {:ok, b2} = Frame.encode(Frame.build(:v1, :response, 3, <<7, 0, 0>>))
      {:ok, b3} = Frame.encode(Frame.build(:v2, :request, 0x0AA4, <<>>))

      assert {[f1, f2, f3], <<>>} = Frame.parse(b1 <> b2 <> b3)
      assert f1.command == 2
      assert f1.data == "INAV"
      assert f2.command == 3
      assert f3.version == :v2
      assert f3.command == 0x0AA4
    end
  end

  describe "parse/1 resilience" do
    test "junk prefix before a valid frame is skipped" do
      {:ok, bytes} = Frame.encode(Frame.build(:v1, :response, 101, <<1>>))
      assert {[frame], <<>>} = Frame.parse(<<0xAB, 0xCD, "hello">> <> bytes)
      assert frame.command == 101
    end

    test "trailing partial frame is returned as remaining buffer" do
      {:ok, full} = Frame.encode(Frame.build(:v1, :response, 101, <<1, 2, 3>>))
      {head, tail} = :erlang.split_binary(full, byte_size(full) - 2)

      assert {[], remaining} = Frame.parse(head)
      # appending the tail completes the frame
      assert {[frame], <<>>} = Frame.parse(remaining <> tail)
      assert frame.command == 101
    end

    test "corrupted CRC is skipped and subsequent frame is still parsed" do
      {:ok, bad} = Frame.encode(Frame.build(:v1, :response, 101, <<1, 2, 3>>))
      bad = :binary.part(bad, 0, byte_size(bad) - 1) <> <<0x00>>
      {:ok, good} = Frame.encode(Frame.build(:v1, :response, 7, <<>>))

      assert {frames, <<>>} = Frame.parse(bad <> good)
      # the bad frame is dropped, the good one still arrives
      assert Enum.any?(frames, &(&1.command == 7))
    end

    test "invalid direction byte is resync'd past" do
      {:ok, good} = Frame.encode(Frame.build(:v1, :response, 5, <<>>))
      noise = <<"$M", 0x00, 0, 0, 0>>
      assert {[frame], <<>>} = Frame.parse(noise <> good)
      assert frame.command == 5
    end

    test "empty buffer returns no frames" do
      assert {[], <<>>} = Frame.parse(<<>>)
    end

    test "bare $ at end of buffer is preserved for next read" do
      assert {[], <<"$">>} = Frame.parse(<<"abc$">>)
    end
  end
end
