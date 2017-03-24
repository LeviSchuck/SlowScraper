defmodule Bacon.Scrape.Client.Queue do
  @moduledoc """
    A cheap and simple queue implementation.
    It is meant to be used with only one worker, although it may support
    multiple in a greedy pull fashion.
  """
  alias Bacon.Scrape.Client.Queue
  use GenServer
  require Logger

  defstruct id: nil, queue: [], pending: %{}, wait: []

  @spec add_request(pid, any, function) :: :ok
  def add_request(pid, url, fun) when is_pid(pid) do
    GenServer.cast(pid, {:queue, url, fun})
  end

  @spec request_work(pid, function) :: :ok
  def request_work(pid, fun) when is_pid(pid) do
    GenServer.cast(pid, {:request_work, fun})
  end
  @type work :: {any, [any]} | nil
  @spec get_request(pid) :: work
  def get_request(pid) when is_pid(pid) do
    GenServer.call(pid, {:get_work})
  end

  def start_link(client) do
    name = {:via, :gproc, {:n, :l, {__MODULE__, client}}}
    GenServer.start_link(__MODULE__, client, name: name)
  end
  def whereis(client) do
    :gproc.whereis_name({:n, :l, {__MODULE__, client}})
  end
  def init(client) do
    state = %Queue{id: client}
    {:ok, state}
  end

  @spec handle_call({:get_work}, GenServer.from, %Queue{})
    :: {:reply, work, %Queue{}}
  def handle_call({:get_work}, _from, %Queue{queue: []} = state) do
    {:reply, nil, state}
  end
  def handle_call({:get_work}, _from, %Queue{queue: [work | queue]} = state) do
    {contexts, npending} = Map.pop(state.pending, work)
    nstate = %{state | queue: queue, pending: npending}
    {:reply, {work, contexts}, nstate}
  end

  @spec handle_cast({:request_work, function}, %Queue{}) :: {:noreply, %Queue{}}
  def handle_cast({:request_work, fun}, %Queue{queue: []} = state) do
    nstate = %{state | wait: [fun | state.wait]}
    {:noreply, nstate}
  end
  def handle_cast({:request_work, fun}, %Queue{} = state) do
    Task.start(fun)
    {:noreply, state}
  end

  @spec handle_cast({:queue, any(), function}, %Queue{}) :: {:noreply, %Queue{}}
  def handle_cast({:queue, url, notify}, %Queue{} = state) do
    # A page has indicated that work is requested for this client
    # Make note of the page in particular and the notify function
    # for that process
    npending = Map.update(state.pending, url, [notify], fn ctxs ->
      [notify | ctxs]
    end)
    # It is possible, although unlikely, for multiple processes to wait on
    # a single URL. Only add the URL to the queue if it isn't already in the
    # queue. This could be more optimal.
    nqueue = if Enum.any?(state.queue, fn x -> x == url end) do
      state.queue
    else
      state.queue ++ [url]
    end
    # If we happen to have any waiting workers, let them know work is available.
    _ = Enum.map(state.wait, fn x -> Task.start(x) end)
    nstate = %{state | queue: nqueue, pending: npending, wait: []}
    {:noreply, nstate}
  end
end
