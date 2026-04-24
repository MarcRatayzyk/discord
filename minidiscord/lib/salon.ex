defmodule MiniDiscord.Salon do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, %{name: name, clients: [], historique: []},
      name: via(name))
  end

  def rejoindre(salon, pid), do: GenServer.call(via(salon), {:rejoindre, pid})
  def quitter(salon, pid),   do: GenServer.call(via(salon), {:quitter, pid})
  def broadcast(salon, msg), do: GenServer.cast(via(salon), {:broadcast, msg})

  # Récupère toutes les clés du registre, c'est-à-dire les noms des salons actifs
  def lister do
    Registry.select(MiniDiscord.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def init(state), do: {:ok, state}

  def handle_call({:rejoindre, pid}, _from, state) do
    # Mettre en place un monitoring sur le processus pour être notifié s'il se termine
    Process.monitor(pid)
    # Envoyer l'historique des 10 derniers messages au nouveau client
    send(pid, {:history, Enum.reverse(state.historique)})
    # Ajouter le client à la liste des clients du salon
    {:reply, :ok, %{state | clients: [pid | state.clients]}}
  end

  def handle_call({:quitter, pid}, _from, state) do
    # Retirer le client de la liste des clients du salon
    {:reply, :ok, %{state | clients: List.delete(state.clients, pid)}}
  end

  def handle_cast({:broadcast, msg}, state) do
    # Ajouter le message à l'historique en gardant seulement les 10 derniers
    historique = [msg | state.historique] |> Enum.take(10)
    # Envoyer le message à tous les clients connectés au salon
    Enum.each(state.clients, fn pid -> send(pid, {:message, msg}) end)
    # Retourner le nouvel état avec l'historique mis à jour
    {:noreply, %{state | historique: historique}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Quand un processus client se termine, le retirer automatiquement de la liste
    {:noreply, %{state | clients: List.delete(state.clients, pid)}}
  end

  defp via(name), do: {:via, Registry, {MiniDiscord.Registry, name}}
end
