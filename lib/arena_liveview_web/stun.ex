# lib/littlechat_web/stun.ex

defmodule ArenaLiveviewWeb.Stun do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  @doc """
  Starts the Erlang STUN server at port 3478.
  """
  def init(_) do
    :stun_listener.add_listener({0,0,0,0}, String.to_integer(System.get_env("STUN_PORT")), :udp, [])

    {:ok, []}
  end
end
