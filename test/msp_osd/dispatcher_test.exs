defmodule MspOsd.DispatcherTest do
  use ExUnit.Case, async: true

  alias MspOsd.{Dispatcher, Frame}

  defmodule EchoDispatcher do
    @behaviour Dispatcher

    @impl true
    def handle_request(%Frame{direction: :request, command: cmd, data: data}) do
      {:reply, Frame.build(:v1, :response, cmd, data)}
    end
  end

  defmodule IgnoringDispatcher do
    @behaviour Dispatcher

    @impl true
    def handle_request(_frame), do: :ignore
  end

  test "Null dispatcher ignores everything" do
    frame = Frame.build(:v1, :request, 2, <<>>)
    assert :ignore = Dispatcher.Null.handle_request(frame)
  end

  test "dispatcher can reply with a response frame" do
    req = Frame.build(:v1, :request, 10, "Ovcs1")
    assert {:reply, reply} = EchoDispatcher.handle_request(req)
    assert reply.direction == :response
    assert reply.command == 10
    assert reply.data == "Ovcs1"
  end

  test "dispatcher can choose to ignore a specific frame" do
    req = Frame.build(:v1, :request, 99, <<>>)
    assert :ignore = IgnoringDispatcher.handle_request(req)
  end
end
