defmodule MspOsd.CommandTest do
  use ExUnit.Case, async: true

  alias MspOsd.Command

  test "round-trips id <-> name for every known command" do
    for {id, name} <- Command.all() do
      assert Command.name(id) == name
      assert Command.id(name) == id
    end
  end

  test "unknown id returns nil" do
    assert Command.name(0xDEAD) == nil
    assert Command.id(:NOT_A_COMMAND) == nil
  end

  test "DisplayPort subcommands round-trip" do
    for name <- [
          :MSP_DP_HEARTBEAT,
          :MSP_DP_RELEASE,
          :MSP_DP_CLEAR_SCREEN,
          :MSP_DP_WRITE_STRING,
          :MSP_DP_DRAW_SCREEN,
          :MSP_DP_OPTIONS,
          :MSP_DP_SYS
        ] do
      id = Command.displayport_subcommand_id(name)
      assert is_integer(id)
      assert Command.displayport_subcommand_name(id) == name
    end
  end
end
