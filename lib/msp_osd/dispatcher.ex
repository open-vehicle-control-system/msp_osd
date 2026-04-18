defmodule MspOsd.Dispatcher do
  @moduledoc """
  Behaviour for modules that turn inbound MSP requests into responses.

  A DisplayPort-driven OSD pipeline acts as a Flight Controller: the VTX
  periodically polls the FC for identity/telemetry with `<` (request) frames
  and the FC replies with `>` (response) frames. A `Dispatcher` encapsulates
  that mapping — it receives an already-parsed `MspOsd.Frame` and either
  returns a response frame to send back, or `:ignore` for unsolicited
  traffic.

  Implementations are stateless from the interface's point of view;
  anything that needs to change over time (live telemetry, canvas state)
  should be kept in a sibling process that the dispatcher reads from.
  """

  alias MspOsd.Frame

  @callback handle_request(Frame.t()) :: :ignore | {:reply, Frame.t()}
end

defmodule MspOsd.Dispatcher.Null do
  @moduledoc """
  Default dispatcher that ignores every inbound request. Useful as a
  scaffolding value until a real dispatcher is wired in.
  """

  @behaviour MspOsd.Dispatcher

  @impl true
  def handle_request(_frame), do: :ignore
end
