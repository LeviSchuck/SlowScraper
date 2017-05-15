defmodule SlowScraper.Client.Page do
  @moduledoc """
    Pages are a temporary cache for requests.
    If the cache is expired, it does not immediately purge the cached value.
    It will still server the cached value if the caller is not willing to wait.
    However, if no value is available, the caller must wait until it is available.
    Pages will self terminate after a number of expiration cycles complete,
    so you should not need to worry about leaks over time for rarely used pages.
  """
  require Logger
  alias SlowScraper.Client.Page
  alias SlowScraper.Client.Queue
  use GenServer

  defstruct id: nil,
    page: nil,
    expire: 60_000_000,
    content: nil,
    stale: 0,
    wait: MapSet.new,
    purge: 5,
    timeout: MapSet.new,
    queued: false

  @spec get_content(pid, timeout) :: any()
  def get_content(pid, timeout) when is_pid(pid) and is_integer(timeout) do
    get_content_int(pid, timeout)
  end
  def get_content(pid, :infinite) when is_pid(pid) do
    get_content_int(pid, :infinite)
  end
  def get_content(pid, :infinity) when is_pid(pid) do
    get_content_int(pid, :infinite)
  end
  defp get_content_int(pid, timeout) do
    res = GenServer.call(pid, {:get_content, timeout})
    case res do
      {:ok, result, stale} -> {:ok, result, stale}
      {:catched_error, err} -> throw err
      {:rescued_error, err} -> raise err
    end
  end
  @spec force_update(pid) :: :ok
  def force_update(pid) when is_pid(pid) do
    GenServer.cast(pid, :force_update)
  end
  @spec force_clear(pid) :: :ok
  def force_clear(pid) when is_pid(pid) do
    GenServer.cast(pid, :force_clear)
  end

  def start_link(client, page, expire \\ 60_000_000, purge \\ 5) do
    name = {:via, :gproc, {:n, :l, {__MODULE__, client, page}}}
    GenServer.start_link(__MODULE__, {client, page, expire, purge}, name: name)
  end
  def whereis(client, page) do
    :gproc.whereis_name({:n, :l, {__MODULE__, client, page}})
  end
  def init({client, page, expire, purge}) do
    state = %Page{id: client, page: page, expire: expire, purge: purge}
    {:ok, state}
  end

  @spec handle_call({:get_content, timeout}, GenServer.from, %Page{})
    :: {:noreply, %Page{}}
    |  {:reply, any(), %Page{}}
  def handle_call({:get_content, _}, from, %Page{content: nil} = state) do
    # There is no content yet, we should request content and wait.
    # A timeout is not applicable to pages without value
    GenServer.cast(self(), :force_update)
    nwait = MapSet.put(state.wait, from)
    nstate = %{state | wait: nwait, stale: make_stale(state.stale)}
    {:noreply, nstate}
  end
  def handle_call({:get_content, timeout}, from, %Page{} = state) do
    isstale = state.stale > 0
    if isstale do
      # When a page is stale, we should
      GenServer.cast(self(), :force_update)
      case timeout do
        :infinite ->
          # The process is willing to wait forever for a non-stale result
          nwait = MapSet.put(state.wait, from)
          nstate = %{state | wait: nwait}
          # Reply later
          {:noreply, nstate}
        0 ->
          # The process is not willing to wait for a non-stale result
          {:reply, {:ok, state.content, true}, state}
        wait_for ->
          # The process is willing to wait wait_for milliseconds
          Process.send_after(self(), {:timeout, from}, wait_for)
          ntimeout = MapSet.put(state.timeout, from)
          nwait = MapSet.put(state.wait, from)
          nstate = %{state | wait: nwait, timeout: ntimeout}
          # Reply later
          {:noreply, nstate}
      end
    else
      # The page content is not stale, send it as is
      {:reply, {:ok, state.content, false}, state}
    end
  end

  @spec handle_cast(:force_update, %Page{}) :: {:noreply, %Page{}}
  def handle_cast(:force_update, %Page{queued: true} = state) do
    # This page has already been queued
    {:noreply, state}
  end
  def handle_cast(:force_update, %Page{} = state) do
    qpid = Queue.whereis(state.id)
    selfref = self()
    # We are forcing an update, but it has to go through the queue first.
    Queue.add_request(qpid, state.page, fn body ->
      GenServer.cast(selfref, {:got_update, body})
    end)
    # In case it was not stale before, it surely is stale now.
    nstate = %{state | stale: make_stale(state.stale), queued: true}
    {:noreply, nstate}
  end

  @spec handle_cast(:force_clear, %Page{}) :: {:noreply, %Page{}}
  def handle_cast(:force_clear, %Page{} = state) do
    nstate = %{state | content: nil}
    {:noreply, nstate}
  end

  @type update_content :: {:ok, any()} | {:catched_error, any()} | {:raised_error, any()}
  @spec handle_cast({:got_update, update_content}, %Page{}) :: {:noreply, %Page{}}
  def handle_cast({:got_update, content}, %Page{} = state) do
    # We got an update, but we need to say when it may no longer be good.
    Process.send_after(self(), {:mark_stale, 0}, state.expire)
    # Let every process waiting know the current page's content
    _ = Enum.map(state.wait, fn from ->
      case content do
        {:ok, result} -> GenServer.reply(from, {:ok, result, false})
        {:rescued_error, err} -> GenServer.reply(from, {:rescued_error, err})
        {:catched_error, err} -> GenServer.reply(from, {:catched_error, err})
      end
    end)
    # Since we responded before the timeout, remove from timeout set
    ntimeout = Enum.reduce(state.wait, state.timeout, fn from, timeout ->
      MapSet.delete(timeout, from)
    end)
    nstale = case content do
      {:ok, _} -> 0
      _ -> 1
    end
    ncontent = case content do
      {:ok, c} -> c
      _ -> nil
    end
    nstate = %{state |
      stale: nstale,
      wait: MapSet.new,
      content: ncontent,
      timeout: ntimeout,
      queued: false
    }
    {:noreply, nstate}
  end

  @spec handle_cast({:mark_stale, integer}, %Page{})
    :: {:noreply, %Page{}}
    |  {:stop, :normal, %Page{}}
  def handle_info({:mark_stale, oldstale}, %Page{} = state) do
    # We use Process.send_after to notify the page that it may be stale
    # However, intermediate clears or other operations may have made it less
    # stale.
    if oldstale <= state.stale do
      # It seems to still be stale
      next_stale = state.stale + 1
      if next_stale >= state.purge do
        # After so many expire cycles of being stale, this page must not be
        # used anymore. Therefore, drop the content and terminate the Process
        # normally.
        nstate = %{state | stale: next_stale, content: nil}
        {:stop, :normal, nstate}
      else
        # Mark this page as more stale than before.
        nstate = %{state | stale: next_stale}
        Process.send_after(self(), {:mark_stale, next_stale}, state.expire)
        {:noreply, nstate}
      end
    else
      # It is not just as or more stale, thus this timed event is invalidated
      {:noreply, state}
    end
  end

  @spec handle_info({:timeout, pid}, %Page{}) :: {:noreply, %Page{}}
  def handle_info({:timeout, from}, %Page{} = state) do
    # A timeout has come in from a previously pended request.
    if MapSet.member?(state.timeout, from) do
      # This request has not been handled
      ntimeout = MapSet.delete(state.timeout, from)
      nstate = %{state | timeout: ntimeout}
      # Let the requesting process know the content, but that it is stale.
      GenServer.reply(from, {:ok, state.content, true})
      {:noreply, nstate}
    else
      # This request has already been handled
      {:noreply, state}
    end
  end
  def handle_info(what, state) do
    Logger.warn "Got unhandled info message #{inspect what}"
    {:noreply, state}
  end
  defp make_stale(s) when s > 0, do: s
  defp make_stale(_), do: 1
end
