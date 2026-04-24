defmodule MiniDiscord.ChatServer do
  use GenServer
  require Logger

  @port 4040

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    {:ok, listen_socket} = :gen_tcp.listen(@port, [
      :binary,
      packet: :line,
      active: false,
      reuseaddr: true
    ])
    Logger.info("🚀 Serveur démarré sur le port #{@port}")
    send(self(), :accept)
    {:ok, Map.put(state, :listen_socket, listen_socket)}
  end

  def handle_info(:accept, %{listen_socket: ls} = state) do
    {:ok, client_socket} = :gen_tcp.accept(ls)
    Task.Supervisor.start_child(
      MiniDiscord.TaskSupervisor,
      fn -> MiniDiscord.ClientHandler.start(client_socket) end
    )
    send(self(), :accept)
    {:noreply, state}
  end
end
