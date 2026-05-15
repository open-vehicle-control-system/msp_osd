defmodule MspOsd.Codec do
  @moduledoc """
  Encoders and decoders for the MSP payloads an OSD pipeline actually reads.

  Every function operates on raw payload bytes (no framing). Wrap the result
  with `MspOsd.Frame.build/5` to emit on the wire, or extract with
  `MspOsd.Frame.parse/1` first and then pass the `data` field here.

  Wire layout references: Betaflight `src/main/msp/msp.c`, INAV
  `src/main/msp/msp_protocol.h`. All multi-byte fields are little-endian.
  """

  # MSP_API_VERSION (1)

  @spec encode_api_version(byte(), byte(), byte()) :: binary()
  def encode_api_version(protocol, major, minor),
    do: <<protocol, major, minor>>

  @spec decode_api_version(binary()) ::
          {:ok, %{protocol: byte(), major: byte(), minor: byte()}} | :error
  def decode_api_version(<<protocol, major, minor>>),
    do: {:ok, %{protocol: protocol, major: major, minor: minor}}

  def decode_api_version(_), do: :error

  # MSP_FC_VARIANT (2) — 4-byte ASCII tag: "BTFL", "INAV", "ARDU", "CLFL".

  @spec encode_fc_variant(String.t()) :: binary()
  def encode_fc_variant(variant) when is_binary(variant) and byte_size(variant) == 4,
    do: variant

  @spec decode_fc_variant(binary()) :: {:ok, String.t()} | :error
  def decode_fc_variant(<<variant::binary-size(4)>>), do: {:ok, variant}
  def decode_fc_variant(_), do: :error

  # MSP_FC_VERSION (3)

  @spec encode_fc_version(byte(), byte(), byte()) :: binary()
  def encode_fc_version(major, minor, patch), do: <<major, minor, patch>>

  @spec decode_fc_version(binary()) ::
          {:ok, %{major: byte(), minor: byte(), patch: byte()}} | :error
  def decode_fc_version(<<major, minor, patch>>),
    do: {:ok, %{major: major, minor: minor, patch: patch}}

  def decode_fc_version(_), do: :error

  # MSP_NAME (10) — free-form ASCII craft name.

  @spec encode_name(String.t()) :: binary()
  def encode_name(name) when is_binary(name), do: name

  @spec decode_name(binary()) :: {:ok, String.t()}
  def decode_name(data) when is_binary(data), do: {:ok, data}

  # MSP_STATUS (101) — minimum Betaflight-compatible fields.

  @spec encode_status(%{
          cycle_time: non_neg_integer(),
          i2c_errors: non_neg_integer(),
          sensor_flags: non_neg_integer(),
          flight_mode_flags: non_neg_integer(),
          profile: byte()
        }) :: binary()
  def encode_status(%{
        cycle_time: cycle,
        i2c_errors: i2c,
        sensor_flags: sensors,
        flight_mode_flags: modes,
        profile: profile
      }) do
    <<cycle::little-16, i2c::little-16, sensors::little-16, modes::little-32, profile>>
  end

  @spec decode_status(binary()) :: {:ok, map()} | :error
  def decode_status(
        <<cycle::little-16, i2c::little-16, sensors::little-16, modes::little-32, profile,
          _rest::binary>>
      ) do
    {:ok,
     %{
       cycle_time: cycle,
       i2c_errors: i2c,
       sensor_flags: sensors,
       flight_mode_flags: modes,
       profile: profile
     }}
  end

  def decode_status(_), do: :error

  # MSP_RAW_GPS (106)

  @spec encode_raw_gps(%{
          fix: byte(),
          num_sat: byte(),
          lat: integer(),
          lon: integer(),
          altitude: non_neg_integer(),
          speed: non_neg_integer(),
          ground_course: non_neg_integer()
        }) :: binary()
  def encode_raw_gps(%{
        fix: fix,
        num_sat: sats,
        lat: lat,
        lon: lon,
        altitude: alt,
        speed: speed,
        ground_course: course
      }) do
    <<fix, sats, lat::signed-little-32, lon::signed-little-32, alt::little-16, speed::little-16,
      course::little-16>>
  end

  @spec decode_raw_gps(binary()) :: {:ok, map()} | :error
  def decode_raw_gps(
        <<fix, sats, lat::signed-little-32, lon::signed-little-32, alt::little-16,
          speed::little-16, course::little-16>>
      ) do
    {:ok,
     %{
       fix: fix,
       num_sat: sats,
       lat: lat,
       lon: lon,
       altitude: alt,
       speed: speed,
       ground_course: course
     }}
  end

  def decode_raw_gps(_), do: :error

  # MSP_COMP_GPS (107)

  @spec encode_comp_gps(%{
          distance_home: non_neg_integer(),
          direction_home: non_neg_integer(),
          heartbeat: byte()
        }) :: binary()
  def encode_comp_gps(%{distance_home: dist, direction_home: dir, heartbeat: hb}) do
    <<dist::little-16, dir::little-16, hb>>
  end

  @spec decode_comp_gps(binary()) :: {:ok, map()} | :error
  def decode_comp_gps(<<dist::little-16, dir::little-16, hb>>) do
    {:ok, %{distance_home: dist, direction_home: dir, heartbeat: hb}}
  end

  def decode_comp_gps(_), do: :error

  # MSP_ATTITUDE (108) — roll/pitch in decidegrees, yaw in whole degrees.

  @spec encode_attitude(%{roll: integer(), pitch: integer(), yaw: integer()}) :: binary()
  def encode_attitude(%{roll: roll, pitch: pitch, yaw: yaw}) do
    <<roll::signed-little-16, pitch::signed-little-16, yaw::signed-little-16>>
  end

  @spec decode_attitude(binary()) :: {:ok, map()} | :error
  def decode_attitude(<<roll::signed-little-16, pitch::signed-little-16, yaw::signed-little-16>>) do
    {:ok, %{roll: roll, pitch: pitch, yaw: yaw}}
  end

  def decode_attitude(_), do: :error

  # MSP_ALTITUDE (109) — altitude in cm, vario in cm/s.

  @spec encode_altitude(%{altitude: integer(), vario: integer()}) :: binary()
  def encode_altitude(%{altitude: alt, vario: vario}) do
    <<alt::signed-little-32, vario::signed-little-16>>
  end

  @spec decode_altitude(binary()) :: {:ok, map()} | :error
  def decode_altitude(<<alt::signed-little-32, vario::signed-little-16>>) do
    {:ok, %{altitude: alt, vario: vario}}
  end

  def decode_altitude(_), do: :error

  # MSP_ANALOG (110) — legacy Betaflight layout.

  @spec encode_analog(%{
          vbat: byte(),
          mah_drawn: non_neg_integer(),
          rssi: non_neg_integer(),
          amperage: integer()
        }) :: binary()
  def encode_analog(%{vbat: vbat, mah_drawn: mah, rssi: rssi, amperage: amp}) do
    <<vbat, mah::little-16, rssi::little-16, amp::signed-little-16>>
  end

  @spec decode_analog(binary()) :: {:ok, map()} | :error
  def decode_analog(<<vbat, mah::little-16, rssi::little-16, amp::signed-little-16>>) do
    {:ok, %{vbat: vbat, mah_drawn: mah, rssi: rssi, amperage: amp}}
  end

  def decode_analog(_), do: :error

  # MSP_BATTERY_STATE (130)

  @spec encode_battery_state(%{
          cell_count: byte(),
          capacity_mah: non_neg_integer(),
          voltage: byte(),
          mah_drawn: non_neg_integer(),
          amperage: integer()
        }) :: binary()
  def encode_battery_state(%{
        cell_count: cells,
        capacity_mah: capacity,
        voltage: voltage,
        mah_drawn: mah,
        amperage: amp
      }) do
    <<cells, capacity::little-16, voltage, mah::little-16, amp::signed-little-16>>
  end

  @spec decode_battery_state(binary()) :: {:ok, map()} | :error
  def decode_battery_state(
        <<cells, capacity::little-16, voltage, mah::little-16, amp::signed-little-16>>
      ) do
    {:ok,
     %{
       cell_count: cells,
       capacity_mah: capacity,
       voltage: voltage,
       mah_drawn: mah,
       amperage: amp
     }}
  end

  def decode_battery_state(_), do: :error
end
