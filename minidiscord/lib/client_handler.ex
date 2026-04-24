defmodule MiniDiscord.ClientHandler do
  require Logger

  def start(socket) do
    :gen_tcp.send(socket, "Bienvenue sur MiniDiscord!\r\n")
    pseudo = demander_pseudo(socket)

    :gen_tcp.send(socket, "Salons disponibles : #{salons_dispo()}\r\n")
    :gen_tcp.send(socket, "Rejoins un salon (ex: general) : ")
    {:ok, salon} = :gen_tcp.recv(socket, 0)
    salon = String.trim(salon)

    rejoindre_salon(socket, pseudo, salon)
  end

  defp demander_pseudo(socket) do
    :gen_tcp.send(socket, "Entre ton pseudo : ")

    case :gen_tcp.recv(socket, 0) do
      {:ok, pseudo} ->
        pseudo = String.trim(pseudo)

        cond do
          pseudo == "" ->
            :gen_tcp.send(socket, "Pseudo invalide, recommence.\r\n")
            demander_pseudo(socket)

          pseudo_disponible?(pseudo) ->
            reserver_pseudo(pseudo)
            pseudo

          true ->
            :gen_tcp.send(socket, "Ce pseudo est déjà pris, choisis-en un autre.\r\n")
            demander_pseudo(socket)
        end

      {:error, _reason} ->
        exit(:client_disconnected)
    end
  end

  defp pseudo_disponible?(pseudo) do
    case :ets.lookup(:pseudos, pseudo) do
      [] -> true
      [_] -> false
    end
  end

  defp reserver_pseudo(pseudo) do
    :ets.insert(:pseudos, {pseudo, self()})
  end

  defp liberer_pseudo(pseudo) do
    :ets.delete(:pseudos, pseudo)
  end

  defp rejoindre_salon(socket, pseudo, salon) do
    case Registry.lookup(MiniDiscord.Registry, salon) do
      [] ->
        DynamicSupervisor.start_child(
          MiniDiscord.SalonSupervisor,
          {MiniDiscord.Salon, salon})
      _ -> :ok
    end

    MiniDiscord.Salon.rejoindre(salon, self())
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    :gen_tcp.send(socket, "Tu es dans ##{salon} — écris tes messages !\r\n")

    loop(socket, pseudo, salon)
  end

  defp loop(socket, pseudo, salon) do
    receive do
      {:message, msg} ->
        :gen_tcp.send(socket, msg)
    after 0 -> :ok
    end

    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, msg} ->
        msg = String.trim(msg)
        MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg}\r\n")
        loop(socket, pseudo, salon)

      {:error, :timeout} ->
        loop(socket, pseudo, salon)

      {:error, reason} ->
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
    end
  end

  defp salons_dispo do
    case MiniDiscord.Salon.lister() do
      [] -> "aucun (tu seras le premier !)"
      salons -> Enum.join(salons, ", ")
    end
  end
end
