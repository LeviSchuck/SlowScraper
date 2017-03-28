defmodule Bacon.Scrape.Client.Worker do
  @moduledoc """
    This worker will throttle what it executes, it will use a user
    provided function on a URL in the queue along with user provided
    context. This may be useful if you want to have different Clients
    operate with different headers, but use the same function overall.
  """
  alias Bacon.Scrape.Client.Queue
  alias Bacon.Scrape.Client.Worker
  alias Bacon.Scrape.Client.Config
  use GenServer
  require Logger

  defstruct id: nil, throttle: 1000, adapter: nil

  def start_link(client, adapter, throttle) do
    name = {:via, :gproc, {:n, :l, {__MODULE__, client}}}
    GenServer.start_link(__MODULE__, {client, adapter, throttle}, name: name)
  end
  def whereis(client) do
    :gproc.whereis_name({:n, :l, {__MODULE__, client}})
  end
  def init({client, adapter, throttle}) do
    GenServer.cast(self(), {:ask_for_work})
    state = %Worker{id: client, adapter: adapter, throttle: throttle}
    {:ok, state}
  end

  @spec handle_cast({:do_work}, %Worker{}) :: {:noreply, %Worker{}}
  def handle_cast({:do_work, work}, %Worker{} = state) do
    # Load the configuration used by the user function
    config = Config.get(Config.whereis(state.id))
    # Execute the user function in another process, and notify all
    # waiting workers of new work
    task_res = Task.async(mk_task_fun(work, config, state))
    # Respect the throttle time as the minimum execution time
    :timer.sleep(state.throttle)
    # Verify completion
    Task.await(task_res)
    # Now that work is complete, ask for more work
    GenServer.cast(self(), {:ask_for_work})
    {:noreply, state}
  end

  @spec handle_cast({:ask_for_work}, %Worker{}) :: {:noreply, %Worker{}}
  def handle_cast({:ask_for_work}, %Worker{} = state) do
    selfpid = self()
    pid = Queue.whereis(state.id)
    Queue.request_work(pid, fn ->
      GenServer.cast(selfpid, {:confirmed_work})
    end)
    {:noreply, state}
  end

  @spec handle_cast({:confirmed_work}, %Worker{}) :: {:noreply, %Worker{}}
  def handle_cast({:confirmed_work}, %Worker{} = state) do
    pid = Queue.whereis(state.id)
    maybe_work = Queue.get_request(pid)
    # When a work available message comes along, ensure that we actually
    # got the work to perform
    case maybe_work do
      nil -> {:noreply, state}
      work ->
        # Indeed, we got the work to perform, handle soon
        GenServer.cast(self(), {:do_work, work})
        {:noreply, state}
    end
  end

  defp mk_task_fun({work, contexts}, config, state) do
    fn ->
      # Execute the user provided function safely
      res = try do
        apply(state.adapter, :scrape, [config, work])
      rescue
        err ->
          Logger.error "Provided function failed: #{inspect err}"
          nil
      end
      # Notify all waiting processes that work is completed
      Enum.map(contexts, mk_cond_func(res))
      :ok
    end
  end

  defp mk_cond_func(res) do
    fn fun ->
      try do
        fun.(res)
      rescue
        err ->
          Logger.error "Notify function failed: #{inspect err}"
          nil
      end
    end
  end
end
