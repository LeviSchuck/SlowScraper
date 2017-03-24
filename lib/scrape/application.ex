defmodule Bacon.Scrape.Application do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias Bacon.Scrape
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(Scrape.Clients.Supervisor, []),
      supervisor(Scrape.Client.Pages.Supervisor, [])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bacon.Scrape.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
