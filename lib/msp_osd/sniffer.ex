defmodule MspOsd.Sniffer.State do
  @moduledoc false

  defstruct [
    :fc_uart_pid,
    :fc_uart_port,
    :vtx_uart_pid,
    :vtx_uart_port,
    :fc_uart_buffer,
    :vtx_uart_buffer,
    :fc_filter
  ]
end

defmodule MspOsd.Sniffer do
  @moduledoc """
  Dev-only dual-UART relay used at the bench to sit between an FC and a VTX
  and observe (or filter) the MSP traffic flowing in both directions.

  Not started by the supervision tree by default; launch it manually with
  `MspOsd.Sniffer.start_link/1` when you need it.
  """

  alias Circuits.UART
  alias MspOsd.{Frame, Sniffer.State}
  require Logger
  use GenServer

  @default_fc_filter []

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    Logger.debug("Starting #{__MODULE__}...")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    fc_port = Keyword.fetch!(opts, :fc_port)
    vtx_port = Keyword.fetch!(opts, :vtx_port)
    baud = Keyword.get(opts, :baud, 115_200)
    fc_filter = Keyword.get(opts, :fc_filter, @default_fc_filter)

    {:ok, vtx_uart_pid} = UART.start_link()
    :ok = UART.open(vtx_uart_pid, vtx_port, speed: baud, active: true)
    {:ok, fc_uart_pid} = UART.start_link()
    :ok = UART.open(fc_uart_pid, fc_port, speed: baud, active: true)

    {:ok,
     %State{
       fc_uart_pid: fc_uart_pid,
       fc_uart_port: fc_port,
       vtx_uart_pid: vtx_uart_pid,
       vtx_uart_port: vtx_port,
       fc_uart_buffer: <<>>,
       vtx_uart_buffer: <<>>,
       fc_filter: fc_filter
     }}
  end

  @impl true
  def handle_info({:circuits_uart, tty, bytes}, state) when tty == state.vtx_uart_port do
    {frames, remaining} = Frame.parse(state.vtx_uart_buffer <> bytes)

    for frame <- frames, {:ok, encoded} = Frame.encode(frame) do
      Logger.debug(fn -> "VTX→FC: #{inspect(frame)}" end)
      UART.write(state.fc_uart_pid, encoded)
    end

    {:noreply, %{state | vtx_uart_buffer: remaining}}
  end

  def handle_info({:circuits_uart, tty, bytes}, state) when tty == state.fc_uart_port do
    {frames, remaining} = Frame.parse(state.fc_uart_buffer <> bytes)

    for frame <- frames,
        frame.command not in state.fc_filter,
        {:ok, encoded} = Frame.encode(frame) do
      Logger.debug(fn -> "FC→VTX: #{inspect(frame)}" end)
      UART.write(state.vtx_uart_pid, encoded)
    end

    {:noreply, %{state | fc_uart_buffer: remaining}}
  end

  def handle_info({:circuits_uart, _tty, {:error, reason}}, state) do
    Logger.warning("Sniffer UART error: #{inspect(reason)}")
    {:noreply, state}
  end
end
