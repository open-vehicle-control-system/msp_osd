defmodule MspOsd.Interface.State do
  @moduledoc false

  defstruct [:uart_pid, :uart_port, :uart_buffer, :dispatcher]
end

defmodule MspOsd.Interface do
  @moduledoc """
  GenServer that owns the serial port to a VTX and bridges between
  `MspOsd.Frame` and the wire.

  Inbound bytes are accumulated, parsed into frames, and routed through
  a `MspOsd.Dispatcher` implementation. Requests (direction `:request`)
  whose dispatcher returns `{:reply, frame}` are encoded and written
  straight back to the VTX; responses and unsolicited pushes are
  logged and dropped unless the dispatcher handles them explicitly.

  Outbound frames are sent via `send/1` — typically called by a
  sibling process that pushes telemetry (`MSP_STATUS`, `MSP_ATTITUDE`,
  ...) and DisplayPort commands on a timer.
  """

  alias Circuits.UART
  alias MspOsd.{Dispatcher, Frame, Interface.State}
  require Logger
  use GenServer

  @empty_buffer <<>>

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(args) do
    Logger.debug("Starting #{__MODULE__}...")
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(%{uart_port: uart_port, uart_baud_rate: uart_baud_rate} = args) do
    {:ok, uart_pid} = UART.start_link()
    :ok = UART.open(uart_pid, uart_port, speed: uart_baud_rate, active: true)

    {:ok,
     %State{
       uart_pid: uart_pid,
       uart_port: uart_port,
       uart_buffer: @empty_buffer,
       dispatcher: Map.get(args, :dispatcher, Dispatcher.Null)
     }}
  end

  @impl true
  def handle_info({:circuits_uart, tty, bytes}, state) when tty == state.uart_port do
    {frames, remaining} = Frame.parse(state.uart_buffer <> bytes)
    Enum.each(frames, &route(&1, state))
    {:noreply, %{state | uart_buffer: remaining}}
  end

  def handle_info({:circuits_uart, _tty, {:error, reason}}, state) do
    Logger.warning("MSP UART error: #{inspect(reason)}")
    {:noreply, state}
  end

  @doc """
  Sends a frame over the UART. Returns `:ok` on success or `{:error, reason}`
  if encoding fails.
  """
  @spec send(Frame.t()) :: :ok | {:error, atom()}
  def send(%Frame{} = frame) do
    GenServer.call(__MODULE__, {:send, frame})
  end

  @impl true
  def handle_call({:send, %Frame{} = frame}, _from, state) do
    case write_frame(frame, state) do
      :ok -> {:reply, :ok, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  defp route(%Frame{direction: :request} = frame, state) do
    case state.dispatcher.handle_request(frame) do
      {:reply, %Frame{} = reply} ->
        case write_frame(reply, state) do
          :ok -> :ok
          {:error, reason} -> Logger.error("MSP reply encode failed: #{inspect(reason)}")
        end

      :ignore ->
        :ok
    end
  end

  defp route(%Frame{} = frame, _state) do
    Logger.debug(fn -> "MSP rx (non-request): #{inspect(frame)}" end)
  end

  defp write_frame(%Frame{} = frame, state) do
    case Frame.encode(frame) do
      {:ok, bytes} -> UART.write(state.uart_pid, bytes)
      {:error, _} = err -> err
    end
  end
end
