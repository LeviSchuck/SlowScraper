defmodule SlowScraper do
  @moduledoc """
  In order to use SlowScraper, you must create a client which will then
  request pages.

  The intent of this library is to slowly scrape a non-API site,
  which may be sensitive to quick successive request behavior.

  This library does not assume what requesting method is used or what
  the result of the request is. httpoison should be good to use.

  Suppose you wished to use httpoison to fetch the HTML for a popular site
  like HackerNews. (There are better tools for this!)


      defmodule BasicHTTP do
        def scrape(headers, url) do
          {:ok, response} = HTTPoison.get(url, headers, [])
          Map.get(response, :body)
        end
      end
      headers_from_config = ["Referer": "https://news.ycombinator.com/"]
      SlowScraper.add_client(:hn, headers_from_config, BasicHTTP)

  Then when you request a page, even if you hit it multiple times
  rapidly, you're only hitting a local cache.

      SlowScraper.request_page(:hn, "https://news.ycombinator.com/newest")

  Many other parameters are available for add_client and request_page to
  control
  * Throttle rate
  * Stale / expire timing
  * Purge cycle count
  * Maximum wait to get a fresh or stale copy of a page

  """
  alias SlowScraper.Client
  alias SlowScraper.Client.Page
  alias SlowScraper.Client.Pages

  @type wait :: integer | :infinity
  @spec client_spec(term, any, function, integer, wait) :: Supervisor.Spec.spec
  def client_spec(client, config, fun, throttle \\ 1_000, max_wait \\ 5_000) do
    import Supervisor.Spec
    supervisor(Client.Supervisor, [client, config, fun, throttle, max_wait])
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
    pid_pages = Pages.Supervisor.whereis(client)
    {:ok, pid_page} = Pages.Supervisor.add_page(
      pid_pages,
      client,
      page,
      expire,
      purge)
    pid_page
  end
  defp read_page(pid, timeout) when is_pid(pid) do
    result = Page.get_content(pid, timeout)
    case result do
      {:ok, content, _} -> content
      _ -> nil
    end
  end
end
