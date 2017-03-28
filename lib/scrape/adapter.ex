defmodule Bacon.Scrape.Adaptor do
  @moduledoc """
  Adapter behavior for executing a scrape command
  """
  @type content :: any
  @type context :: any
  @type url :: String.t
  @callback scrape(context, url) :: content
end
