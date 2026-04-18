defmodule MspOsd.DisplayPort do
  @moduledoc """
  Helpers that produce `MSP_DISPLAYPORT` (command 182) frames ready to send
  over an `MspOsd.Interface`.

  DisplayPort is the VTX-side OSD canvas protocol used by HDZero, Walksnail
  and DJI. The FC (or an FC-impersonating pipeline like this library) owns
  the canvas and pushes subcommands to:

    - negotiate canvas resolution (`options/1`)
    - keep the link alive (`heartbeat/0`)
    - clear the canvas (`clear/0`)
    - draw text at a cell (`write_string/4`)
    - flush the frame (`draw/0`)
    - release the canvas back to the VTX (`release/0`)
    - push native warnings (`sys/1`)

  All functions return `%MspOsd.Frame{}` structs that `MspOsd.Interface.send/1`
  serialises on the wire. Every frame is tagged as a response (`:response`)
  because a DisplayPort-enabled FC is the canonical source of OSD data.
  """

  alias MspOsd.{Command, Frame}

  @displayport_cmd Command.id(:MSP_DISPLAYPORT)

  @resolutions %{
    sd_3016: 0,
    hd_5018: 1,
    hd_3016: 2,
    hd_5320: 3
  }

  @attr_flags %{
    page1: 0x01,
    blink: 0x02,
    invert: 0x04
  }

  @type resolution :: :sd_3016 | :hd_5018 | :hd_3016 | :hd_5320
  @type attr_flag :: :page1 | :blink | :invert
  @type attrs :: [attr_flag()] | non_neg_integer()

  @doc """
  Advertises canvas resolution + font selector to the VTX.

  `font_selector` is 0 for the default font, non-zero for OEM fonts on some
  HD VTX firmware.
  """
  @spec options(resolution(), byte()) :: Frame.t()
  def options(resolution, font_selector \\ 0)
      when is_map_key(@resolutions, resolution) and font_selector in 0..255 do
    sub = Command.displayport_subcommand_id(:MSP_DP_OPTIONS)
    payload = <<sub, font_selector, Map.fetch!(@resolutions, resolution)>>
    displayport_frame(payload)
  end

  @spec heartbeat() :: Frame.t()
  def heartbeat do
    sub = Command.displayport_subcommand_id(:MSP_DP_HEARTBEAT)
    displayport_frame(<<sub>>)
  end

  @spec clear() :: Frame.t()
  def clear do
    sub = Command.displayport_subcommand_id(:MSP_DP_CLEAR_SCREEN)
    displayport_frame(<<sub>>)
  end

  @spec draw() :: Frame.t()
  def draw do
    sub = Command.displayport_subcommand_id(:MSP_DP_DRAW_SCREEN)
    displayport_frame(<<sub>>)
  end

  @spec release() :: Frame.t()
  def release do
    sub = Command.displayport_subcommand_id(:MSP_DP_RELEASE)
    displayport_frame(<<sub>>)
  end

  @doc """
  Writes `text` at `(row, col)` with optional character attributes.

  `attrs` can be a list of `:page1 | :blink | :invert` or a raw byte. Rows
  and columns must fit inside the canvas the caller advertised via
  `options/2`; this function does not range-check because the canvas is
  chosen by the pipeline, not the library.
  """
  @spec write_string(byte(), byte(), String.t(), attrs()) :: Frame.t()
  def write_string(row, col, text, attrs \\ [])
      when row in 0..255 and col in 0..255 and is_binary(text) do
    sub = Command.displayport_subcommand_id(:MSP_DP_WRITE_STRING)
    payload = <<sub, row, col, attrs_to_byte(attrs)>> <> text
    displayport_frame(payload)
  end

  @doc """
  Pushes a "system" element onto the VTX — armed warning, low-battery, etc.
  Payload semantics are VTX-specific; see the HDZero/Walksnail docs.
  """
  @spec sys(binary()) :: Frame.t()
  def sys(payload) when is_binary(payload) do
    sub = Command.displayport_subcommand_id(:MSP_DP_SYS)
    displayport_frame(<<sub>> <> payload)
  end

  @spec attrs_to_byte(attrs()) :: byte()
  def attrs_to_byte(byte) when is_integer(byte) and byte in 0..255, do: byte

  def attrs_to_byte(flags) when is_list(flags) do
    Enum.reduce(flags, 0, fn flag, acc ->
      Bitwise.bor(acc, Map.fetch!(@attr_flags, flag))
    end)
  end

  defp displayport_frame(payload) do
    Frame.build(:v1, :response, @displayport_cmd, payload)
  end
end
