defmodule MiniDiscord.ClientHandler do
  # un processus par client tcp
  require Logger

  def start(socket) do#fonction appelée à chaque nouvelle connexion
    :gen_tcp.send(socket, "Bienvenue sur MiniDiscord!\r\n")
    # boucle jusqu'à pseudo libre dans ets
    pseudo = demander_pseudo(socket)#verifie que le pseudo est dispo

    :gen_tcp.send(socket, "Salons disponibles : #{salons_dispo()}\r\n")#affiche les salons déjà créés
    :gen_tcp.send(socket, "Rejoins un salon (ex: general) : ")
    {:ok, salon} = :gen_tcp.recv(socket, 0)#recv = attend une réponse du client
    salon = String.trim(salon)

    rejoindre_salon(socket, pseudo, salon)#rejoindre le salon demandé ou le créer si inexistant
  end

  defp demander_pseudo(socket) do#fonction qui boucle pour demander un pseudo valide
    :gen_tcp.send(socket, "Entre ton pseudo : ")

    case :gen_tcp.recv(socket, 0) do
      {:ok, pseudo} ->
        pseudo = String.trim(pseudo)

        cond do
          pseudo == "" ->#si pseudo vide
            :gen_tcp.send(socket, "Pseudo invalide, recommence.\r\n")
            demander_pseudo(socket)

          pseudo_disponible?(pseudo) ->
            reserver_pseudo(pseudo)
            pseudo

          true ->#si pseudo déjà pris
            :gen_tcp.send(socket, "Ce pseudo est déjà pris, choisis-en un autre.\r\n")
            demander_pseudo(socket)
        end

      {:error, _reason} ->#si client quitte
        exit(:client_disconnected)
    end
  end

  defp pseudo_disponible?(pseudo) do#verifie la validité du pseudo
    # [] = libre
    case :ets.lookup(:pseudos, pseudo) do
      [] -> true
      [_] -> false
    end
  end

  defp reserver_pseudo(pseudo) do#enregistre le pseudo dans ets avec le pid du handler pour libération à la déconnexion
    # self() = ce handler, pour debug éventuel
    :ets.insert(:pseudos, {pseudo, self()})
  end

  defp liberer_pseudo(pseudo) do#liberation pseudo
    :ets.delete(:pseudos, pseudo)
  end

  defp rejoindre_salon(socket, pseudo, salon) do#fonction qui permet de rejoindre un salon
    case Registry.lookup(MiniDiscord.Registry, salon) do
      [] ->
        DynamicSupervisor.start_child(
          MiniDiscord.SalonSupervisor,
          {MiniDiscord.Salon, salon}
        )#lance une task pour gérer le salon

      _ ->#si salon existant ok
        :ok
    end

    MiniDiscord.Salon.rejoindre(salon, self())
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    :gen_tcp.send(socket, "Tu es dans ##{salon} — écris tes messages !\r\n")

    loop(socket, pseudo, salon)
  end

  defp flush_incoming(socket) do#fonction qui affiche les messages reçus
    receive do#
      {:message, msg} ->
        :gen_tcp.send(socket, msg)
        flush_incoming(socket)

      {:history, msgs} ->
        Enum.each(msgs, fn ligne -> :gen_tcp.send(socket, ligne) end)
        flush_incoming(socket)
    after
      # plus rien en attente
      0 ->
        :ok
    end
  end

  defp loop(socket, pseudo, salon) do#fonctuon qui boucle pour recevoir les messages
    flush_incoming(socket)

    case :gen_tcp.recv(socket, 0, 100) do#permet de recevoir un message du client avec un timeout pour flush les messages en attente
      {:ok, msg} ->
        msg = String.trim(msg)

        cond do
          msg == "" ->#si message vide
            loop(socket, pseudo, salon)#on reste dans la boucle pour attendre un message non vide

          String.starts_with?(msg, "/") ->#cas d'une commande
            case gerer_commande(socket, pseudo, salon, msg) do
              :quit ->
                :ok

              {:continue, nouveau_salon} ->
                loop(socket, pseudo, nouveau_salon)
            end

          true ->
            # message normal vers tout le salon
            MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg}\r\n")
            loop(socket, pseudo, salon)
        end

      {:error, :timeout} ->
        # pas de frappe : on retourne au début pour flush
        loop(socket, pseudo, salon)

      {:error, reason} ->#si client déconnecté ou autre erreur
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
    end
  end

  defp gerer_commande(socket, pseudo, salon, commande) do
    cond do
      commande == "/list" ->#affiche la liste des salons disponibles
        noms = MiniDiscord.Salon.lister() |> Enum.sort()
        texte = if noms == [], do: "(aucun salon pour l'instant)", else: Enum.join(noms, ", ")
        # privé : pas de broadcast
        :gen_tcp.send(socket, "Salons actifs : #{texte}\r\n")
        {:continue, salon}

      commande == "/quit" ->#quitte le salon et libère le pseudo
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
        :gen_tcp.send(socket, "À bientôt !\r\n")
        :gen_tcp.close(socket)
        :quit

      String.starts_with?(commande, "/join ") ->#rejoindre ou créer un salon
        nouveau = commande |> String.replace_prefix("/join ", "") |> String.trim()

        if nouveau == "" do
          :gen_tcp.send(socket, "Usage : /join <nom_du_salon>\r\n")
          {:continue, salon}
        else
          changer_salon(socket, pseudo, salon, nouveau)
        end

      true ->#commande inconnue
        :gen_tcp.send(socket, "Commande inconnue\r\n")
        {:continue, salon}
    end
  end

  defp changer_salon(socket, pseudo, ancien, nouveau) do#fonction pour changer de salon
    if nouveau == ancien do
      :gen_tcp.send(socket, "Tu es déjà dans ##{nouveau}\r\n")
      {:continue, ancien}
    else#cas normal
      MiniDiscord.Salon.broadcast(ancien, "👋 #{pseudo} a quitté ##{ancien}\r\n")#message pour tout le monde
      MiniDiscord.Salon.quitter(ancien, self())

      case Registry.lookup(MiniDiscord.Registry, nouveau) do#si salon existe pas création
        [] ->
          DynamicSupervisor.start_child(
            MiniDiscord.SalonSupervisor,
            {MiniDiscord.Salon, nouveau}
          )

        _ ->
          :ok
      end

      MiniDiscord.Salon.rejoindre(nouveau, self())#rejoindre le nouveau salon
      MiniDiscord.Salon.broadcast(nouveau, "📢 #{pseudo} a rejoint ##{nouveau}\r\n")
      :gen_tcp.send(socket, "Tu es dans ##{nouveau} — écris tes messages !\r\n")
      {:continue, nouveau}
    end
  end

  defp salons_dispo do#fonction pour afficher les salons
    case MiniDiscord.Salon.lister() do
      [] -> "aucun (tu seras le premier !)"
      salons -> salons |> Enum.sort() |> Enum.join(", ")
    end
  end
end
