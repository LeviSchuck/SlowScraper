defmodule Bacon.Scrape do
  @moduledoc """
  In order to use Bacon.Scrape, you must create a client which will then
  request pages.

  The intent of this library is to slowly scrape a non-API site,
  which may be sensitive to quick successive request behavior.

  This library does not assume what requesting method is used or what
  the result of the request is. httpoison should be good to use.

  Suppose you wished to use httpoison to fetch the HTML for a popular site
  like HackerNews. (There are better tools for this!)

      headers_from_config = ["Referer": "https://news.ycombinator.com/"]
      request_fun = fn url, headers ->
        {:ok, response} = HTTPoison.get(url, headers, [])
        Map.get(response, :body)
      end
      Bacon.Scrape.add_client(:hn, headers_from_config, request_fun)

  Then when you request a page, even if you hit it multiple times
  rapidly, you're only hitting a local cache.

      Bacon.Scrape.request_page(:hn, "https://news.ycombinator.com/newest")

  Many other parameters are available for add_client and request_page to
  control
  * Throttle rate
  * Stale / expire timing
  * Purge cycle count
  * Maximum wait to get a fresh or stale copy of a page

  """
  alias Bacon.Scrape.Clients
  alias Bacon.Scrape.Client.Page
  alias Bacon.Scrape.Client.Pages

  @spec add_client(term, any, function, integer) :: Supervisor.on_start()
  def add_client(client, config, fun, throttle \\ 1_000) do
    pid = Clients.Supervisor.whereis()
    Clients.Supervisor.add_client(pid, client, config, fun, throttle)
  end

  @spec request_page(term, any, integer, integer, timeout) :: any
  def request_page(client, page,
    expire \\ 60_000_000,
    purge \\ 5,
    max_wait \\ 4_000) do
    maybe_pid_page = Page.whereis(client, page)
    pid_page = case maybe_pid_page do
      :undefined -> make_page(client, page, expire, purge)
      pid when is_pid(pid) -> pid
    end
    read_page(pid_page, max_wait)
  end

  defp make_page(client, page, expire, purge) do
    pid_pages = Pages.Supervisor.whereis()
    {:ok, pid_page} = Pages.Supervisor.add_page(
      pid_pages,
      client,
      page,
      expire,
      purge)
    pid_page
  end
  defp read_page(pid, timeout) when is_pid(pid) do
    case Page.get_content(pid, timeout) do
      {content, _} -> content
      _ -> nil
    end
  end
end
