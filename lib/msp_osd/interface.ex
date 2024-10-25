defmodule MspOsd.Interface.State do
  defstruct [:uart_pid, :uart_port, :uart_buffer]
end

defmodule MspOsd.Interface do
  alias MspOsd.Interface.State
  alias MspOsd.MspMessageBuilder
  alias Circuits.UART
  require Logger
  use GenServer

  @empty_buffer <<>>

  def init(%{uart_port: uart_port, uart_baud_rate: uart_baud_rate}) do
    {:ok, uart_pid} = UART.start_link
    :ok             = UART.open(uart_pid, uart_port, speed: uart_baud_rate, active: true)

    schedule_msp_status()
    schedule_msp_displayport_hearbeat()
    schedule_test()

    {:ok, %State{
        uart_pid: uart_pid,
        uart_port: uart_port,
        uart_buffer: @empty_buffer
      }
    }
  end

  @spec start_link(nil) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    Logger.debug "Starting #{__MODULE__}..."
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def handle_info({:circuits_uart, tty, _frame}, state) when tty == state.uart_port do
    # {msp_message, buffer} = MspMessageBuilder.search_complete_message_from_buffer(state.uart_buffer <> frame)
    # if msp_message, do: UART.write(state.fc_uart_pid,  msp_message |> MspMessageBuilder.inspect(label: "From VTx to FC") |> MspMessageBuilder.to_frame)
    {:noreply, state}
  end

  def handle_info(:send_msp_status, state) do
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 101, <<250, 3, 0, 0, 131, 0, 16, 0, 8, 0, 0>>) |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 3, <<7, 0, 0>>) |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 2, "INAV") |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)

    schedule_msp_status()
    {:noreply, state}
  end

  def handle_info(:send_msp_display_port_hearbeat, state) do
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 182, <<0>>) |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)

    schedule_msp_displayport_hearbeat()
    {:noreply, state}
  end

  def handle_info(:test, state) do
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 182, <<5, 0, 4>>) |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 182, <<2>>) |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 182, <<3, 3, 2, 0 >> <> "LOIC COUCOUazertyuiop") |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)
    UART.write(state.uart_pid, MspMessageBuilder.build(">", 182, <<3, 4, 2, 0 >> <> "#{:os.system_time(:milli_seconds)}") |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)

    UART.write(state.uart_pid, MspMessageBuilder.build(">", 182, <<4>>) |> MspMessageBuilder.inspect(label: "to VTX") |> MspMessageBuilder.to_frame)
    schedule_test()
    {:noreply, state}
  end

  @spec schedule_msp_status() :: reference()
  def schedule_msp_status do
    Process.send_after(self(), :send_msp_status, 250)
  end

  def schedule_msp_displayport_hearbeat do
    Process.send_after(self(), :send_msp_display_port_hearbeat, 50)
  end

  def schedule_test do
    Process.send_after(self(), :test, 10)
  end

  def write(x, y, text) do
    GenServer.cast(self(), {:write_text, x, y, text})
  end
end


# From FC to VTX: %{
#   command: 101,
#   data: <<247, 3, 0, 0, 131, 0, 16, 0, 8, 0, 0>>,
#   size: 11,
#   direction: ">",
#   command_name: "MSP_STATUS",
#   crc: 1,
#   direction_name: "Response: Slave -> Master"
# }
# From FC to VTX: %{
#   command: 3,
#   data: <<7, 0, 0>>,
#   size: 3,
#   direction: ">",
#   command_name: "MSP_FC_VERSION",
#   crc: 7,
#   direction_name: "Response: Slave -> Master"
# }
# From FC to VTX: %{
#   command: 3,
#   data: <<7, 0, 0>>,
#   size: 3,
#   direction: ">",
#   command_name: "MSP_FC_VERSION",
#   crc: 7,
#   direction_name: "Response: Slave -> Master"
# }
# From FC to VTX: %{
#   command: 2,
#   data: "INAV",
#   size: 4,
#   direction: ">",
#   command_name: "MSP_FC_VARIANT",
#   crc: 22,
#   direction_name: "Response: Slave -> Master"
# }
# From FC to VTX: %{
#   command: 3,
#   data: "",
#   size: 0,
#   direction: "!",
#   command_name: "MSP_FC_VERSION",
#   crc: 3,
#   direction_name: "Error"
# }
# From FC to VTX: %{
#   command: 2,
#   data: "INAV",
#   size: 4,
#   direction: ">",
#   command_name: "MSP_FC_VARIANT",
#   crc: 22,
#   direction_name: "Response: Slave -> Master"
# }

# From FC to VTX: %{
#   command: 182,
#   data: <<0>>,
#   size: 1,
#   direction: ">",
#   crc: 183,
#   direction_name: "Response: Slave -> Master",
#   command_name: "MSP_DISPLAYPORT",
#   display_port_sub_command: 0,
#   display_port_sub_command_name: "MSP_DP_HEARTBEAT"
# }
# From FC to VTX: %{
#   command: 182,
#   data: <<5, 0, 4>>,
#   size: 3,
#   direction: ">",
#   crc: 180,
#   direction_name: "Response: Slave -> Master",
#   command_name: "MSP_DISPLAYPORT",
#   display_port_sub_command: 5,
#   display_port_sub_command_name: "MSP_DP_OPTIONS"
# }
# From FC to VTX: %{
#   command: 182,
#   data: <<2>>,
#   size: 1,
#   direction: ">",
#   crc: 181,
#   direction_name: "Response: Slave -> Master",
#   command_name: "MSP_DISPLAYPORT",
#   display_port_sub_command: 2,
#   display_port_sub_command_name: "MSP_DP_CLEAR_SCREEN"
# }
# From FC to VTX: %{
#   command: 182,
#   data: <<0>>,
#   size: 1,
#   direction: ">",
#   crc: 183,
#   direction_name: "Response: Slave -> Master",
#   command_name: "MSP_DISPLAYPORT",
#   display_port_sub_command: 0,
#   display_port_sub_command_name: "MSP_DP_HEARTBEAT"
# }
# From FC to VTX: %{
#   command: 182,
#   data: <<3, 3, 2, 0, 161, 183, 53, 106>>,
#   size: 8,
#   direction: ">",
#   crc: 245,
#   direction_name: "Response: Slave -> Master",
#   command_name: "MSP_DISPLAYPORT",
#   display_port_sub_command: 3,
#   display_port_sub_command_name: "MSP_DP_WRITE_STRING"
# }
# From FC to VTX: %{
#   command: 182,
#   data: <<4>>,
#   size: 1,
#   direction: ">",
#   crc: 179,
#   direction_name: "Response: Slave -> Master",
#   command_name: "MSP_DISPLAYPORT",
#   display_port_sub_command: 4,
#   display_port_sub_command_name: "MSP_DP_DRAW_SCREEN"
# }
