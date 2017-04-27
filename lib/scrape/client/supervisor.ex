defmodule SlowScraper.Client.Supervisor do
  @moduledoc false
  alias SlowScraper.Client
  use Supervisor
  require Logger

  def start_link(client, config, fun, throttle) do
    name = {:via, :gproc, {:n, :l, {__MODULE__, client}}}
    param = {client, config, fun, throttle}
    Supervisor.start_link(__MODULE__, param, name: name)
  end
  def whereis(client) do
    :gproc.whereis_name({:n, :l, {__MODULE__, client}})
  end
  def init({client, config, fun, throttle}) do
    children = [
      supervisor(Client.Pages.Supervisor, [client]),
      worker(Client.Config, [client, config]),
      worker(Client.Queue, [client]),
      worker(Client.Worker, [client, fun, throttle]),
    ]
    supervise(children, strategy: :rest_for_one)
  end
end
