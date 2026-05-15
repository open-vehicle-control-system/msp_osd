defmodule MspOsd.DisplayPortTest do
  use ExUnit.Case, async: true

  alias MspOsd.{DisplayPort, Frame}

  defp subcmd(%Frame{command: 182, data: <<sub, _::binary>>}), do: sub

  describe "subcommand shape" do
    test "heartbeat is <<0>>" do
      frame = DisplayPort.heartbeat()
      assert frame.command == 182
      assert frame.direction == :response
      assert frame.data == <<0>>
      assert subcmd(frame) == 0
    end

    test "release is <<1>>" do
      assert DisplayPort.release().data == <<1>>
    end

    test "clear is <<2>>" do
      assert DisplayPort.clear().data == <<2>>
    end

    test "draw is <<4>>" do
      assert DisplayPort.draw().data == <<4>>
    end

    test "options for HD 53x20 is <<5, 0, 3>>" do
      assert DisplayPort.options(:hd_5320).data == <<5, 0, 3>>
    end

    test "options for SD 30x16 is <<5, 0, 0>>" do
      assert DisplayPort.options(:sd_3016).data == <<5, 0, 0>>
    end

    test "options accepts a font selector" do
      assert DisplayPort.options(:hd_5320, 2).data == <<5, 2, 3>>
    end
  end

  describe "write_string/4" do
    test "no attrs => <<3, row, col, 0, text...>>" do
      frame = DisplayPort.write_string(3, 5, "HELLO")
      assert frame.data == <<3, 3, 5, 0>> <> "HELLO"
    end

    test "attrs list turns into bit flags" do
      frame = DisplayPort.write_string(0, 0, "X", [:blink, :invert])
      assert frame.data == <<3, 0, 0, 0x06>> <> "X"
    end

    test "raw attr byte is passed through" do
      frame = DisplayPort.write_string(1, 2, "Y", 0x07)
      assert frame.data == <<3, 1, 2, 0x07>> <> "Y"
    end

    test "page1 flag lights bit 0" do
      frame = DisplayPort.write_string(0, 0, "z", [:page1])
      assert frame.data == <<3, 0, 0, 0x01, ?z>>
    end

    test "empty text is valid (position + attrs only)" do
      frame = DisplayPort.write_string(7, 11, "")
      assert frame.data == <<3, 7, 11, 0>>
    end
  end

  describe "sys/1" do
    test "wraps payload with subcommand 6" do
      assert DisplayPort.sys(<<0xAB, 0xCD>>).data == <<6, 0xAB, 0xCD>>
    end
  end

  describe "attrs_to_byte/1" do
    test "empty list -> 0" do
      assert DisplayPort.attrs_to_byte([]) == 0
    end

    test "all flags -> 0x07" do
      assert DisplayPort.attrs_to_byte([:page1, :blink, :invert]) == 0x07
    end
  end

  test "all DisplayPort frames round-trip through Frame.encode/Frame.parse" do
    frames = [
      DisplayPort.heartbeat(),
      DisplayPort.clear(),
      DisplayPort.draw(),
      DisplayPort.release(),
      DisplayPort.options(:hd_5320),
      DisplayPort.write_string(2, 3, "ALT 120", [:blink])
    ]

    encoded =
      frames
      |> Enum.map(fn f ->
        {:ok, bytes} = Frame.encode(f)
        bytes
      end)
      |> IO.iodata_to_binary()

    {decoded, <<>>} = Frame.parse(encoded)
    assert Enum.map(decoded, & &1.data) == Enum.map(frames, & &1.data)
  end
end
