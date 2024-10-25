defmodule MspOsd.MspMessageBuilder do
  alias MspOsd.Domain.MspMessage
  import Bitwise

  @msp_commands %{
    "2"   => [name: "MSP_FC_VARIANT"],
    "3"   => [name: "MSP_FC_VERSION"],
    "100" => [name: "MSP_IDENT"],
    "101" => [name: "MSP_STATUS", hide: false],
    "182" => [name: "MSP_DISPLAYPORT"]
  }

  @msp_display_port_subcommands %{
    "0"   => [name: "MSP_DP_HEARTBEAT"],
    "1"   => [name: "MSP_DP_RELEASE"],
    "2"   => [name: "MSP_DP_CLEAR_SCREEN"],
    "3"   => [name: "MSP_DP_WRITE_STRING"],
    "4"   => [name: "MSP_DP_DRAW_SCREEN"],
    "5"   => [name: "MSP_DP_OPTIONS"],
    "6"   => [name: "MSP_DP_SYS"]
  }


  def build(<< direction >>, command, data) do
    %MspMessage{direction: direction, size: byte_size(data), command: command, data: data}
  end

  @spec build_from_frame(any(), any(), any(), any()) :: none()
  def build_from_frame(direction, size, command, data, crc \\ nil) do
    msp_message = %MspMessage{direction: direction, size: size, command: command, data: data}
    if (crc == (msp_message |> crc)), do: nil, else: raise "Invalid CRC"
    msp_message
  end

  def search_complete_message_from_buffer(<<36, 77, direction::size(8), size::size(8), command::size(8), data::binary-size(size), crc::size(8), buffer::binary>>) do
    msp_message = build_from_frame(direction, size, command, data, crc)
    {msp_message, buffer}
  end

  def search_complete_message_from_buffer(<<_, buffer::binary>>) do
    {nil, buffer}
  end

  def to_frame(msp_message) do
    "$M" <> << msp_message.direction, msp_message.size, msp_message.command>> <> msp_message.data <> << (msp_message |> crc) >>
  end
  def inspect(msp_message, args) do
    data = Map.merge(%{
      direction:      msp_message |> direction,
      direction_name: msp_message |> direction_name,
      command:        msp_message.command,
      command_name:   msp_message |> command_name,
      size:           msp_message.size,
      data:           msp_message.data,
      crc:            msp_message |> crc
    }, inspect_display_port(msp_message))
    data |> IO.inspect(args)
    msp_message
  end

  def inspect_display_port(msp_message) when msp_message.command == 182 do
    %{
      display_port_sub_command:      msp_message |> display_port_sub_command,
      display_port_sub_command_name: msp_message |> display_port_sub_command_name
    }
  end

  def inspect_display_port(_msp_message) do
    %{}
  end

  def crc(msp_message) do
    bxor(bxor(msp_message.size, msp_message.command), crc_data(msp_message.data || 0))
  end

  def crc_data("") do
    0
  end

  def crc_data(<< byte >>) do
    byte
  end

  def crc_data(<< byte, data::binary>>) do
    bxor(byte, crc_data(data))
  end

  def direction(msp_message) do
    << msp_message.direction::utf8 >>
  end

  def direction_name(msp_message) do
    case msp_message |> direction do
      "<" -> "Request: Master -> Slave"
      ">" -> "Response: Slave -> Master"
      "!" -> "Error"
    end
  end

  def command_name(msp_message) do
    @msp_commands["#{msp_message.command}"][:name]
  end

  def display_port_sub_command(msp_message) do
    case msp_message.command do
      182 ->
        << sub_command::size(8), _data::binary >> = msp_message.data
        sub_command
      _ -> nil
    end
  end

  def display_port_sub_command_name(msp_message) do
    @msp_display_port_subcommands["#{msp_message |> display_port_sub_command}"][:name]
  end
end
