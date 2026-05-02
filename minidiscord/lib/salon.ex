defmodule MiniDiscord.Salon do
  # genserver = processus avec état + callbacks
  use GenServer

  def start_link(name) do
    # état : nom du salon, liste des pid clients, 10 derniers messages
    GenServer.start_link(__MODULE__, %{name: name, clients: [], historique: []},
      name: via(name))
  end

  # api synchrone : on attend :ok
  def rejoindre(salon, pid), do: GenServer.call(via(salon), {:rejoindre, pid})
  def quitter(salon, pid), do: GenServer.call(via(salon), {:quitter, pid})
  # cast = fire and forget, pas de réponse
  def broadcast(salon, msg), do: GenServer.cast(via(salon), {:broadcast, msg})

  # toutes les clés = noms des salons vivants
  def lister do
    Registry.select(MiniDiscord.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def init(state), do: {:ok, state}

  def handle_call({:rejoindre, pid}, _from, state) do
    #lien avec le client : mort du pid -> message :DOWN
    Process.monitor(pid)
    #envoi des anciens messages au nouveau (ordre lecture)
    send(pid, {:history, Enum.reverse(state.historique)})
    #ajout du pid en tête de liste
    {:reply, :ok, %{state | clients: [pid | state.clients]}}
  end

  def handle_call({:quitter, pid}, _from, state) do
    #enlève ce client du salon
    {:reply, :ok, %{state | clients: List.delete(state.clients, pid)}}
  end

  def handle_cast({:broadcast, msg}, state) do
    #max 10 lignes, les plus récentes d'abord dans la liste
    historique = [msg | state.historique] |> Enum.take(10)
    #un send par client abonné
    Enum.each(state.clients, fn pid -> send(pid, {:message, msg}) end)
    {:noreply, %{state | historique: historique}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    #client mort : on le retire sans attendre un quitter explicite
    {:noreply, %{state | clients: List.delete(state.clients, pid)}}
  end

  #enregistre le processus sous le nom du salon dans le registry
  defp via(name), do: {:via, Registry, {MiniDiscord.Registry, name}}
end
