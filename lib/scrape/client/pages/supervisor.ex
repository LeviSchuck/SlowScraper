defmodule Bacon.Scrape.Client.Pages.Supervisor do
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
      supervisor(Client.Page, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
  def add_page(supervisor, client, page, expire, purge) when is_pid(supervisor) do
    Supervisor.start_child(supervisor, [client, page, expire, purge])
  end
end
