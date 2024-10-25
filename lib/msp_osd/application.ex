defmodule MspOsd.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []
    children = if Application.get_env(:msp_osd, :enabled), do: children ++ [{MspOsd.Interface, Application.get_env(:msp_osd, :interface)}], else: children

    opts = [strategy: :one_for_one, name: MspOsd.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
