defmodule MspOsd.CodecTest do
  use ExUnit.Case, async: true

  alias MspOsd.Codec

  describe "MSP_API_VERSION" do
    test "round-trip" do
      bytes = Codec.encode_api_version(0, 1, 46)
      assert byte_size(bytes) == 3
      assert {:ok, %{protocol: 0, major: 1, minor: 46}} = Codec.decode_api_version(bytes)
    end

    test "rejects malformed input" do
      assert :error = Codec.decode_api_version(<<1, 2>>)
    end
  end

  describe "MSP_FC_VARIANT" do
    test "4-byte tag round-trip" do
      assert {:ok, "INAV"} = Codec.decode_fc_variant(Codec.encode_fc_variant("INAV"))
      assert {:ok, "BTFL"} = Codec.decode_fc_variant(Codec.encode_fc_variant("BTFL"))
    end

    test "wrong length decoded to :error" do
      assert :error = Codec.decode_fc_variant(<<1, 2, 3>>)
    end
  end

  describe "MSP_FC_VERSION" do
    test "round-trip" do
      bytes = Codec.encode_fc_version(7, 1, 0)
      assert {:ok, %{major: 7, minor: 1, patch: 0}} = Codec.decode_fc_version(bytes)
    end
  end

  describe "MSP_NAME" do
    test "free-form ASCII" do
      {:ok, "Ovcs1"} = Codec.decode_name(Codec.encode_name("Ovcs1"))
      {:ok, ""} = Codec.decode_name(Codec.encode_name(""))
    end
  end

  describe "MSP_STATUS" do
    test "round-trip" do
      status = %{
        cycle_time: 250,
        i2c_errors: 0,
        sensor_flags: 0x0083,
        flight_mode_flags: 0x00010008,
        profile: 0
      }

      bytes = Codec.encode_status(status)
      assert {:ok, ^status} = Codec.decode_status(bytes)
    end

    test "ignores trailing bytes from newer FCs" do
      status = %{
        cycle_time: 250,
        i2c_errors: 0,
        sensor_flags: 0,
        flight_mode_flags: 0,
        profile: 0
      }

      bytes = Codec.encode_status(status) <> <<0xAA, 0xBB, 0xCC>>
      assert {:ok, ^status} = Codec.decode_status(bytes)
    end
  end

  describe "MSP_RAW_GPS" do
    test "round-trip with negative lat/lon" do
      gps = %{
        fix: 1,
        num_sat: 12,
        lat: -505_340_123,
        lon: 43_216_789,
        altitude: 150,
        speed: 1200,
        ground_course: 27_000
      }

      assert {:ok, ^gps} = Codec.decode_raw_gps(Codec.encode_raw_gps(gps))
    end
  end

  describe "MSP_COMP_GPS" do
    test "round-trip" do
      comp = %{distance_home: 1234, direction_home: 355, heartbeat: 1}
      assert {:ok, ^comp} = Codec.decode_comp_gps(Codec.encode_comp_gps(comp))
    end
  end

  describe "MSP_ATTITUDE" do
    test "signed values round-trip" do
      att = %{roll: -1200, pitch: 800, yaw: -179}
      assert {:ok, ^att} = Codec.decode_attitude(Codec.encode_attitude(att))
    end
  end

  describe "MSP_ALTITUDE" do
    test "negative altitude and vario round-trip" do
      alt = %{altitude: -500, vario: -250}
      assert {:ok, ^alt} = Codec.decode_altitude(Codec.encode_altitude(alt))
    end
  end

  describe "MSP_ANALOG" do
    test "round-trip" do
      analog = %{vbat: 168, mah_drawn: 950, rssi: 1023, amperage: -50}
      assert {:ok, ^analog} = Codec.decode_analog(Codec.encode_analog(analog))
    end
  end

  describe "MSP_BATTERY_STATE" do
    test "round-trip" do
      bat = %{cell_count: 6, capacity_mah: 3300, voltage: 250, mah_drawn: 1200, amperage: 420}
      assert {:ok, ^bat} = Codec.decode_battery_state(Codec.encode_battery_state(bat))
    end
  end
end
