defmodule SlowScraper.Client.Supervisor do
  @moduledoc false
  alias SlowScraper.Client
  use Supervisor
  require Logger

  def start_link(client, config, fun, throttle, max_wait) do
    name = {:via, :gproc, {:n, :l, {__MODULE__, client}}}
    param = {client, config, fun, throttle, max_wait}
    Supervisor.start_link(__MODULE__, param, name: name)
  end
  def whereis(client) do
    :gproc.whereis_name({:n, :l, {__MODULE__, client}})
  end
  def init({client, config, fun, throttle, max_wait}) do
    children = [
      supervisor(Client.Pages.Supervisor, [client], restart: :permanent),
      worker(Client.Config, [client, config], restart: :permanent),
      worker(Client.Queue, [client], restart: :permanent),
      worker(Client.Worker, [client, fun, throttle, max_wait], restart: :permanent),
    ]
    supervise(children, strategy: :rest_for_one)
  end
end
