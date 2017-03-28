defmodule Bacon.Scrape.Clients.Supervisor do
  @moduledoc false
  alias Bacon.Scrape.Client
  use Supervisor

  def start_link do
    name = {:via, :gproc, {:n, :l, {__MODULE__}}}
    Supervisor.start_link(__MODULE__, {}, name: name)
  end
  def whereis do
    :gproc.whereis_name({:n, :l, {__MODULE__}})
  end
  def init({}) do
    children = [
      supervisor(Client.Supervisor, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
  def add_client(supervisor, id, config, adapter, throttle) when is_pid(supervisor) and is_atom(adapter) do
    Supervisor.start_child(supervisor, [id, config, adapter, throttle])
  end
end
