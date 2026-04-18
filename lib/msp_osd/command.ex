defmodule MspOsd.Command do
  @moduledoc """
  Registry of MSP command IDs relevant to OSD rendering.

  Names match the identifiers used by Betaflight / INAV (`msp_protocol.h`).
  The set is intentionally limited to what a DisplayPort-driven OSD actually
  needs; adding a new command here is a one-line change.
  """

  @commands %{
    1 => :MSP_API_VERSION,
    2 => :MSP_FC_VARIANT,
    3 => :MSP_FC_VERSION,
    4 => :MSP_BOARD_INFO,
    5 => :MSP_BUILD_INFO,
    10 => :MSP_NAME,
    82 => :MSP_RX_CONFIG,
    84 => :MSP_OSD_CONFIG,
    86 => :MSP_OSD_CHAR_WRITE,
    100 => :MSP_IDENT,
    101 => :MSP_STATUS,
    104 => :MSP_MOTOR,
    105 => :MSP_RC,
    106 => :MSP_RAW_GPS,
    107 => :MSP_COMP_GPS,
    108 => :MSP_ATTITUDE,
    109 => :MSP_ALTITUDE,
    110 => :MSP_ANALOG,
    130 => :MSP_BATTERY_STATE,
    150 => :MSP_STATUS_EX,
    182 => :MSP_DISPLAYPORT
  }

  @names Map.new(@commands, fn {id, name} -> {name, id} end)

  @displayport_subcommands %{
    0 => :MSP_DP_HEARTBEAT,
    1 => :MSP_DP_RELEASE,
    2 => :MSP_DP_CLEAR_SCREEN,
    3 => :MSP_DP_WRITE_STRING,
    4 => :MSP_DP_DRAW_SCREEN,
    5 => :MSP_DP_OPTIONS,
    6 => :MSP_DP_SYS
  }

  @subcommand_names Map.new(@displayport_subcommands, fn {id, name} -> {name, id} end)

  @spec name(non_neg_integer()) :: atom() | nil
  def name(id), do: Map.get(@commands, id)

  @spec id(atom()) :: non_neg_integer() | nil
  def id(name), do: Map.get(@names, name)

  @spec all() :: %{non_neg_integer() => atom()}
  def all, do: @commands

  @spec displayport_subcommand_name(non_neg_integer()) :: atom() | nil
  def displayport_subcommand_name(id), do: Map.get(@displayport_subcommands, id)

  @spec displayport_subcommand_id(atom()) :: non_neg_integer() | nil
  def displayport_subcommand_id(name), do: Map.get(@subcommand_names, name)
end
