# msp_osd

Elixir library that speaks MSP and DisplayPort so an OVCS vehicle can push
its own OSD onto an MSP-compatible VTX (HDZero, Walksnail, DJI HD).

The library is transport-agnostic in design (UART is the default, other
backends are a future extension) and layered so consumers pick the level
they need:

| Module                | Purpose                                         |
|-----------------------|-------------------------------------------------|
| `MspOsd.Crc`          | XOR8 (MSPv1) + CRC-8/DVB-S2 (MSPv2)             |
| `MspOsd.Frame`        | Framing + parsing for v1, v1 jumbo, v2, v2-over-v1 |
| `MspOsd.Command`      | MSP command-ID ↔ name registry                  |
| `MspOsd.Codec`        | Encoders / decoders for the OSD-relevant MSP payloads |
| `MspOsd.DisplayPort`  | `MSP_DISPLAYPORT` helpers (heartbeat, clear, write, draw, release, options, sys) |
| `MspOsd.Dispatcher`   | Behaviour for turning inbound requests into responses |
| `MspOsd.Interface`    | GenServer that owns the UART and routes frames through the dispatcher |
| `MspOsd.Sniffer`      | Dev-only dual-UART relay for bench debugging    |

## Framing support

`MspOsd.Frame.encode/1` and `parse/1` handle all three wire variants:

- **MSPv1** — `$M<dir><size><cmd><data><xor8>`. Size byte `0xFF` enables the
  *jumbo* variant with a 16-bit little-endian size (payloads up to 64 KB).
- **MSPv2 native** — `$X<dir><flag><cmd:u16><size:u16><data><crc8_dvb_s2>`.
- **MSPv2 over v1** — MSPv2 payload wrapped in an MSPv1 frame with outer
  command `0xFF`, for stacks that kept v1 framing.

The parser is tolerant: bad CRCs and bad direction bytes are skipped one
byte at a time (rather than crashing), and incomplete buffers are returned
verbatim so the caller can append more bytes and retry.

## DisplayPort

`MspOsd.DisplayPort` returns ready-to-send `Frame` structs for every
`MSP_DISPLAYPORT` subcommand:

```elixir
alias MspOsd.{DisplayPort, Interface}

Interface.send(DisplayPort.options(:hd_5320))
Interface.send(DisplayPort.clear())
Interface.send(DisplayPort.write_string(2, 10, "ALT 120", [:blink]))
Interface.send(DisplayPort.draw())
Interface.send(DisplayPort.heartbeat())       # every ~50 ms
Interface.send(DisplayPort.release())         # on shutdown
```

Resolutions: `:sd_3016`, `:hd_5018`, `:hd_3016`, `:hd_5320`. Character
attributes: `:page1`, `:blink`, `:invert` (list or raw byte).

## Dispatcher

A VTX polls the FC for identity + telemetry with `:request` frames. Your
application implements the `MspOsd.Dispatcher` behaviour and plugs it into
the interface; it gets a parsed `Frame` and returns either
`{:reply, Frame.t()}` or `:ignore`.

```elixir
defmodule MyApp.MspDispatcher do
  @behaviour MspOsd.Dispatcher
  alias MspOsd.{Codec, Command, Frame}

  @impl true
  def handle_request(%Frame{command: 2}) do
    {:reply, Frame.build(:v1, :response, 2, Codec.encode_fc_variant("OVCS"))}
  end

  def handle_request(%Frame{command: 3}) do
    {:reply, Frame.build(:v1, :response, 3, Codec.encode_fc_version(0, 1, 0))}
  end

  def handle_request(_), do: :ignore
end
```

## Configuration

The interface is started by `MspOsd.Application` when `:enabled` is true:

```elixir
# config/runtime.exs
config :msp_osd,
  enabled: true,
  interface: %{
    uart_port: "ttyUSB0",
    uart_baud_rate: 115_200,
    dispatcher: MyApp.MspDispatcher
  }
```

`dispatcher` defaults to `MspOsd.Dispatcher.Null` (ignores every request).

## Running against real hardware

1. Plug the VTX into a USB-serial adapter (HDZero and Walksnail both speak
   115 200 baud; some Walksnail builds prefer 230 400 or 420 000).
2. Configure `:msp_osd` as above with the right `/dev/ttyUSBn`.
3. Start the app. The VTX will begin polling for MSP_FC_VARIANT /
   MSP_API_VERSION / MSP_STATUS etc.; your dispatcher replies with the
   values the OSD should display.

For bench debugging, `MspOsd.Sniffer` can sit between a real FC and a real
VTX and relay MSP traffic between them while logging every frame:

```elixir
MspOsd.Sniffer.start_link(fc_port: "ttyUSB1", vtx_port: "ttyUSB0")
```

## Tests

```
mix test
```

Coverage includes CRC math, every framing variant, multi-frame buffers,
corrupt-CRC resync, partial-frame buffering, command table round-trips,
every payload codec, DisplayPort subcommand shapes, and dispatcher
behaviour contract.
