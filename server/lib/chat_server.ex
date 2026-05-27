defmodule MiniDiscord.ChatServer do
  use GenServer
  require Logger

  @port 4040

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    # mode ligne, passive : on recv nous-mêmes
    {:ok, listen_socket} = :gen_tcp.listen(@port, [
      :binary,
      packet: :line,
      active: false,
      reuseaddr: true
    ])#ça peremt de réutiliser le port immédiatement après un redémarrage
    Logger.info("Serveur démarré sur le port #{@port}")
    # boucle d'accept : premier message à traiter
    send(self(), :accept)
    {:ok, Map.put(state, :listen_socket, listen_socket)}
  end

  def handle_info(:accept, %{listen_socket: ls} = state) do#focntion appelée à chaque nouvelle connexion
    {:ok, client_socket} = :gen_tcp.accept(ls)
    # chaque connexion = processus séparé (task)
    Task.Supervisor.start_child(
      MiniDiscord.TaskSupervisor,
      fn -> MiniDiscord.ClientHandler.start(client_socket) end
    )#lance une task pour gérer le client
    # réaccepte tout de suite le suivant
    send(self(), :accept)
    {:noreply, state}
  end
end
