# Bacon.Scrape

The intent of this library is to slowly scrape a non-API site,
which may be sensitive to quick successive request behavior.

This library does not assume what requesting method is used or what
the result of the request is. httpoison should be good to use.

Suppose you wished to use httpoison to fetch the HTML for a popular site
like HackerNews. (There are better tools for this!)

```elixir
defmodule BasicHTTP do
  def scrape(headers, url) do
    {:ok, response} = HTTPoison.get(url, headers, [])
    Map.get(response, :body)
  end
end
headers_from_config = ["Referer": "https://news.ycombinator.com/"]
Bacon.Scrape.add_client(:hn, headers_from_config, BasicHTTP)
```

Then when you request a page, even if you hit it multiple times
rapidly, you're only hitting a local cache.

```elixir
Bacon.Scrape.request_page(:hn, "https://news.ycombinator.com/newest")
```
Many other parameters are available for add_client and request_page to
control
* Throttle rate
* Stale / expire timing
* Purge cycle count
* Maximum wait to get a fresh or stale copy of a page

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `slow_scraper` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:slow_scraper, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/slow_scraper](https://hexdocs.pm/slow_scraper).
