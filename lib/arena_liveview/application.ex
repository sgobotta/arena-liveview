defmodule ArenaLiveview.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      ArenaLiveview.Repo,
      # Start the Telemetry supervisor
      ArenaLiveviewWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: ArenaLiveview.PubSub},
      # Start the Endpoint (http/https)
      ArenaLiveviewWeb.Endpoint,
      ArenaLiveviewWeb.Presence,
      ArenaLiveviewWeb.Stun
      # Start a worker by calling: ArenaLiveview.Worker.start_link(arg)
      # {ArenaLiveview.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArenaLiveview.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ArenaLiveviewWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
