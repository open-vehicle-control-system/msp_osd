defmodule MspOsd.Frame do
  @moduledoc """
  MSP frame representation + encode/parse for all three wire variants:

  - `:v1` — classic `$M<dir><size><cmd><data><xor8>`. Size byte 0xFF enables
    the "jumbo" variant with a 16-bit little-endian size field.
  - `:v2` — native MSPv2 `$X<dir><flag><cmd:u16><size:u16><data><dvb_s2>`.
  - `:v2_over_v1` — MSPv2 payload tunnelled inside an MSPv1 frame whose outer
    command byte is 0xFF. Used by stacks that have to keep MSPv1 framing for
    backwards compat while still transporting v2 messages.

  The parser is tolerant: on a CRC mismatch it resynchronises by skipping one
  byte past the failed preamble. On an incomplete frame it returns the
  buffer tail starting from the preamble so the caller can append more
  bytes and retry.
  """

  alias MspOsd.Crc

  @mspv1_preamble "$M"
  @mspv2_preamble "$X"
  @jumbo_marker 0xFF
  @v2_over_v1_cmd 0xFF

  @type version :: :v1 | :v2 | :v2_over_v1
  @type direction :: :request | :response | :error
  @type t :: %__MODULE__{
          version: version(),
          direction: direction(),
          flag: byte(),
          command: non_neg_integer(),
          data: binary()
        }

  defstruct version: :v1, direction: :request, flag: 0, command: 0, data: <<>>

  @spec build(version(), direction(), non_neg_integer(), binary(), keyword()) :: t()
  def build(version, direction, command, data, opts \\ [])
      when version in [:v1, :v2, :v2_over_v1] and
             direction in [:request, :response, :error] and
             is_integer(command) and command >= 0 and
             is_binary(data) do
    %__MODULE__{
      version: version,
      direction: direction,
      command: command,
      data: data,
      flag: Keyword.get(opts, :flag, 0)
    }
  end

  @spec encode(t()) :: {:ok, binary()} | {:error, atom()}
  def encode(%__MODULE__{version: :v1, command: cmd}) when cmd > 0xFF,
    do: {:error, :command_out_of_range_for_v1}

  def encode(%__MODULE__{version: :v1} = frame) do
    size = byte_size(frame.data)

    cond do
      size <= 0xFE ->
        header = <<size::size(8), frame.command::size(8)>>
        crc = Crc.xor8(header <> frame.data)

        {:ok,
         @mspv1_preamble <> direction_byte(frame.direction) <> header <> frame.data <> <<crc>>}

      size <= 0xFFFF ->
        header = <<@jumbo_marker, frame.command::size(8), size::little-size(16)>>
        crc = Crc.xor8(header <> frame.data)

        {:ok,
         @mspv1_preamble <> direction_byte(frame.direction) <> header <> frame.data <> <<crc>>}

      true ->
        {:error, :payload_too_large}
    end
  end

  def encode(%__MODULE__{version: :v2} = frame) do
    size = byte_size(frame.data)

    if size > 0xFFFF do
      {:error, :payload_too_large}
    else
      inner = v2_inner_bytes(frame.flag, frame.command, size, frame.data)
      crc = Crc.dvb_s2(inner)
      {:ok, @mspv2_preamble <> direction_byte(frame.direction) <> inner <> <<crc>>}
    end
  end

  def encode(%__MODULE__{version: :v2_over_v1} = frame) do
    size = byte_size(frame.data)

    if size > 0xFFFF do
      {:error, :payload_too_large}
    else
      inner = v2_inner_bytes(frame.flag, frame.command, size, frame.data)
      v2_crc = Crc.dvb_s2(inner)
      payload = inner <> <<v2_crc>>
      encode(%__MODULE__{frame | version: :v1, command: @v2_over_v1_cmd, data: payload})
    end
  end

  @doc """
  Parses as many frames as possible from `buffer`.

  Returns `{frames, remaining_buffer}`. `remaining_buffer` contains any
  trailing bytes that are either an incomplete frame or junk awaiting resync.
  """
  @spec parse(binary()) :: {[t()], binary()}
  def parse(buffer) when is_binary(buffer), do: scan(buffer, [])

  defp scan(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp scan(<<"$M", rest::binary>> = buffer, acc) do
    case parse_v1(rest) do
      {:ok, frame, remaining} -> scan(remaining, [frame | acc])
      :incomplete -> {Enum.reverse(acc), buffer}
      :invalid -> scan(skip_byte(buffer), acc)
    end
  end

  defp scan(<<"$X", rest::binary>> = buffer, acc) do
    case parse_v2(rest) do
      {:ok, frame, remaining} -> scan(remaining, [frame | acc])
      :incomplete -> {Enum.reverse(acc), buffer}
      :invalid -> scan(skip_byte(buffer), acc)
    end
  end

  defp scan(<<"$">> = buffer, acc), do: {Enum.reverse(acc), buffer}

  defp scan(<<_byte, rest::binary>>, acc), do: scan(rest, acc)

  defp skip_byte(<<_byte, rest::binary>>), do: rest

  defp parse_v1(<<>>), do: :incomplete
  defp parse_v1(<<dir, _rest::binary>>) when dir not in [?<, ?>, ?!], do: :invalid

  defp parse_v1(<<dir, rest::binary>>) do
    parse_v1_header(direction_atom(dir), rest)
  end

  defp parse_v1_header(direction, <<@jumbo_marker, cmd, size::little-size(16), rest::binary>>) do
    crc_header = <<@jumbo_marker, cmd::size(8), size::little-size(16)>>
    parse_v1_body(direction, cmd, size, crc_header, rest)
  end

  defp parse_v1_header(direction, <<size, cmd, rest::binary>>) when size != @jumbo_marker do
    crc_header = <<size::size(8), cmd::size(8)>>
    parse_v1_body(direction, cmd, size, crc_header, rest)
  end

  defp parse_v1_header(_direction, _rest), do: :incomplete

  defp parse_v1_body(direction, cmd, size, crc_header, buffer) do
    case buffer do
      <<data::binary-size(size), crc, tail::binary>> ->
        if Crc.xor8(crc_header <> data) == crc do
          {:ok, v1_to_frame(direction, cmd, data), tail}
        else
          :invalid
        end

      _ ->
        :incomplete
    end
  end

  defp v1_to_frame(direction, @v2_over_v1_cmd, payload) do
    case parse_v2_inner(payload) do
      {:ok, flag, cmd, data} ->
        %__MODULE__{
          version: :v2_over_v1,
          direction: direction,
          flag: flag,
          command: cmd,
          data: data
        }

      :error ->
        %__MODULE__{version: :v1, direction: direction, command: @v2_over_v1_cmd, data: payload}
    end
  end

  defp v1_to_frame(direction, cmd, data) do
    %__MODULE__{version: :v1, direction: direction, command: cmd, data: data}
  end

  defp parse_v2_inner(<<flag, cmd::little-size(16), size::little-size(16), rest::binary>>) do
    case rest do
      <<data::binary-size(size), crc>> ->
        inner = <<flag, cmd::little-size(16), size::little-size(16)>> <> data

        if Crc.dvb_s2(inner) == crc do
          {:ok, flag, cmd, data}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp parse_v2_inner(_), do: :error

  defp parse_v2(<<dir, flag, cmd::little-size(16), size::little-size(16), rest::binary>>)
       when dir in [?<, ?>, ?!] do
    case rest do
      <<data::binary-size(size), crc, tail::binary>> ->
        inner = <<flag, cmd::little-size(16), size::little-size(16)>> <> data

        if Crc.dvb_s2(inner) == crc do
          frame = %__MODULE__{
            version: :v2,
            direction: direction_atom(dir),
            flag: flag,
            command: cmd,
            data: data
          }

          {:ok, frame, tail}
        else
          :invalid
        end

      _ ->
        :incomplete
    end
  end

  defp parse_v2(<<dir, _::binary>>) when dir not in [?<, ?>, ?!], do: :invalid
  defp parse_v2(_), do: :incomplete

  defp v2_inner_bytes(flag, command, size, data) do
    <<flag, command::little-size(16), size::little-size(16)>> <> data
  end

  defp direction_byte(:request), do: "<"
  defp direction_byte(:response), do: ">"
  defp direction_byte(:error), do: "!"

  defp direction_atom(?<), do: :request
  defp direction_atom(?>), do: :response
  defp direction_atom(?!), do: :error
end
