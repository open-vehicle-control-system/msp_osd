defmodule MspOsd.Sniffer.State do
  defstruct [:fc_uart_pid, :fc_uart_port, :vtx_uart_pid, :vtx_uart_port, :fc_uart_buffer, :vtx_uart_buffer]
end

defmodule MspOsd.Sniffer do
  alias MspOsd.Sniffer.State
  alias MspOsd.MspMessageBuilder
  alias Circuits.UART
  require Logger
  use GenServer

  def init(nil) do
    {:ok, vtx_uart_pid} = Circuits.UART.start_link
    :ok                 = UART.open(vtx_uart_pid, "ttyUSB0", speed: 115_200, active: true)
    {:ok, fc_uart_pid}  = Circuits.UART.start_link
    :ok                 = UART.open(fc_uart_pid, "ttyUSB1", speed: 115_200, active: true)

    {:ok, %State{
        fc_uart_pid: fc_uart_pid,
        fc_uart_port: "ttyUSB1",
        vtx_uart_pid: vtx_uart_pid,
        vtx_uart_port: "ttyUSB0",
        fc_uart_buffer: <<>>,
        vtx_uart_buffer: <<>>
      }
    }
  end

  def start_link(nil) do
    Logger.debug "Starting #{__MODULE__}..."
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def handle_info({:circuits_uart, tty, frame}, state) when tty == state.vtx_uart_port do
    {msp_message, buffer} = MspMessageBuilder.search_complete_message_from_buffer(state.vtx_uart_buffer <> frame)
    if msp_message, do: UART.write(state.fc_uart_pid,  msp_message |> MspMessageBuilder.to_frame)
    {:noreply, %{state | vtx_uart_buffer: buffer}}
  end

  def handle_info({:circuits_uart, tty, frame}, state) when tty == state.fc_uart_port do
    {msp_message, buffer} = MspMessageBuilder.search_complete_message_from_buffer(state.fc_uart_buffer <> frame)
    case msp_message do
      nil -> nil
      msp_message when (msp_message.command == 101) -> nil
      msp_message when (msp_message.command == 2) -> nil
      msp_message when (msp_message.command == 3) -> nil

      _ -> UART.write(state.vtx_uart_pid, msp_message |> MspMessageBuilder.inspect(label: "From FC to VTX") |> MspMessageBuilder.to_frame)
    end
    {:noreply, %{state | fc_uart_buffer: buffer}}
  end
end
