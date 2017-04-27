defmodule SlowScraper.Client.Config do
  @moduledoc """
    This is a dumb and simple contextual config holder that is specific
    to each client as an Agent process.
  """
  def start_link(id, config) do
    name = {:via, :gproc, {:n, :l, {__MODULE__, id}}}
    Agent.start_link(fn ->
      config
    end, name: name)
  end
  def whereis(id) do
    :gproc.whereis_name({:n, :l, {__MODULE__, id}})
  end
  @spec get(pid) :: any()
  def get(pid) when is_pid(pid) do
    Agent.get(pid, fn x -> x end)
  end
end
