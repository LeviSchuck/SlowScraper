defmodule Bacon.ScrapeTest do
  use ExUnit.Case
  require Logger
  doctest Bacon.Scrape
  def fake_context, do: {1,2,3}
  defmodule FakeRequest do
    def start_link() do
      Agent.start_link(fn ->
        %{}
      end)
    end
    def make_request(pid, url) do
      Agent.get_and_update(pid, fn v ->
        nm = Map.update(v, url, 1, fn mv ->
          mv + 1
        end)
        {Map.get(nm, url), nm}
      end)
    end
    def get(pid, url) do
      Agent.get(pid, fn v -> Map.get(v, url) end)
    end
  end
  defmodule FakeAdapter do
    @behaviour Bacon.Scrape.Adaptor
    def scrape(context, url) do
      ctx = Bacon.ScrapeTest.fake_context
      case context do
        {^ctx, agent} -> FakeRequest.make_request(agent, url)
        _ -> nil
      end
    end
  end

  test "basic functionality" do
    wait = 5
    purge = 9001
    {:ok, agent} = FakeRequest.start_link()
    ctx = fake_context()
    req_page = fn page, time ->
      Bacon.Scrape.request_page(:test1, page, wait, purge, time)
    end
    assert FakeRequest.make_request(agent, :test0) == 1
    {:ok, _} = Bacon.Scrape.add_client(:test1, {ctx, agent}, FakeAdapter, wait)
    # 0 shouldn't matter in the case of never having retrieved it before
    first = req_page.(:page1, 0)
    assert first == 1
    # Because we immediately request again, we should get the same thing (cached)
    second = req_page.(:page1, :infinite)
    assert second == 1
    assert FakeRequest.get(agent, :page1) == 1

    # Wait awhile for the cache to go stale
    :timer.sleep(wait*2)
    # The next time we should be requesting (in truth) the second time
    third = req_page.(:page1, :infinite)
    assert third == 2
    assert FakeRequest.get(agent, :page1) == 2
    # Ensure that pages are separate
    another = req_page.(:page2, wait)
    assert another == 1
    assert FakeRequest.get(agent, :page2) == 1
    # Let's lean on the throttling on a second page to make page1 stale again.
    req_page.(:page3, 0)
    forth = req_page.(:page1, :infinite)
    assert forth == 3
    assert FakeRequest.get(agent, :page1) == 3
  end
end
