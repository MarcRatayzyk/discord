defmodule MiniDiscord.ClientHandler do
  # un processus par client tcp
  require Logger

  # Clé partagée (32 octets hex). Doit être la même que dans le client.
  @key Base.decode16!("00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF", case: :mixed)

  @doc """
  Valide un message avant envoi ou réception.
  Retourne {:ok, msg} si le message est valide
  Retourne {:error, raison} sinon
  """
  def valider_message(msg) do
    msg = String.trim(msg)

    cond do
      msg == "" ->
        {:error, "Message vide"}

      String.length(msg) > 500 ->
        {:error, "Message trop long (max 500 chars)"}

      String.contains?(msg, ["<", ">", "?", "\\", "\0"]) ->
        {:error, "Message contient des caractères non autorisés"}

      true ->
        {:ok, msg}
    end
  end

  def start(socket) do
    :gen_tcp.send(socket, encrypt("Bienvenue sur MiniDiscord!\r\n"))

    # boucle jusqu'à pseudo libre dans ets
    pseudo = demander_pseudo(socket)

    :gen_tcp.send(socket, encrypt("Salons disponibles : #{salons_dispo()}\r\n"))
    :gen_tcp.send(socket, encrypt("Rejoins un salon (ex: general) : "))

    case :gen_tcp.recv(socket, 0) do
      {:ok, bin} ->
        case decrypt(bin) do
          {:ok, salon} ->
            salon = String.trim(salon)
            rejoindre_salon(socket, pseudo, salon)
          {:error, _} -> exit(:client_disconnected)
        end

      {:error, _} -> exit(:client_disconnected)
    end
  end

  defp demander_pseudo(socket) do
    :gen_tcp.send(socket, encrypt("Entre ton pseudo : "))

    case :gen_tcp.recv(socket, 0) do
      {:ok, bin} ->
        case decrypt(bin) do
          {:ok, pseudo} ->
            pseudo = String.trim(pseudo)

            cond do
              pseudo == "" ->
                :gen_tcp.send(socket, encrypt("Pseudo invalide, recommence.\r\n"))
                demander_pseudo(socket)

              pseudo_disponible?(pseudo) ->
                reserver_pseudo(pseudo)
                pseudo

              true ->
                :gen_tcp.send(socket, encrypt("Ce pseudo est déjà pris, choisis-en un autre.\r\n"))
                demander_pseudo(socket)
            end

          {:error, _} ->
            exit(:client_disconnected)
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
          {MiniDiscord.Salon, salon}
        )

      _ -> :ok
    end

    MiniDiscord.Salon.rejoindre(salon, self())
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    :gen_tcp.send(socket, encrypt("Tu es dans ##{salon} — écris tes messages !\r\n"))

    loop(socket, pseudo, salon)
  end

  defp flush_incoming(socket) do
    receive do
      {:message, msg} ->
        :gen_tcp.send(socket, encrypt(msg))
        flush_incoming(socket)

      {:history, msgs} ->
        Enum.each(msgs, fn ligne -> :gen_tcp.send(socket, encrypt(ligne)) end)
        flush_incoming(socket)
    after
      0 -> :ok
    end
  end

  defp loop(socket, pseudo, salon) do
    flush_incoming(socket)

    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, bin} ->
        case decrypt(bin) do
          {:ok, plain} ->
            case valider_message(plain) do
              {:error, _raison} -> loop(socket, pseudo, salon)
              {:ok, msg_valide} ->
                cond do
                  String.starts_with?(msg_valide, "/") ->
                    case gerer_commande(socket, pseudo, salon, msg_valide) do
                      :quit -> :ok
                      {:continue, nouveau_salon} -> loop(socket, pseudo, nouveau_salon)
                    end

                  true ->
                    MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg_valide}\r\n")
                    loop(socket, pseudo, salon)
                end
            end

          {:error, _} ->
            # message invalide / non déchiffrable
            loop(socket, pseudo, salon)
        end

      {:error, :timeout} -> loop(socket, pseudo, salon)

      {:error, reason} ->
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
    end
  end

  defp gerer_commande(socket, pseudo, salon, commande) do
    cond do
      commande == "/list" ->
        noms = MiniDiscord.Salon.lister() |> Enum.sort()
        texte = if noms == [], do: "(aucun salon pour l'instant)", else: Enum.join(noms, ", ")
        :gen_tcp.send(socket, encrypt("Salons actifs : #{texte}\r\n"))
        {:continue, salon}

      commande == "/quit" ->
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
        :gen_tcp.send(socket, encrypt("À bientôt !\r\n"))
        :gen_tcp.close(socket)
        :quit

      String.starts_with?(commande, "/join ") ->
        nouveau = commande |> String.replace_prefix("/join ", "") |> String.trim()

        if nouveau == "" do
          :gen_tcp.send(socket, encrypt("Usage : /join <nom_du_salon>\r\n"))
          {:continue, salon}
        else
          changer_salon(socket, pseudo, salon, nouveau)
        end

      true ->
        :gen_tcp.send(socket, encrypt("Commande inconnue\r\n"))
        {:continue, salon}
    end
  end

  defp changer_salon(socket, pseudo, ancien, nouveau) do
    if nouveau == ancien do
      :gen_tcp.send(socket, encrypt("Tu es déjà dans ##{nouveau}\r\n"))
      {:continue, ancien}
    else
      MiniDiscord.Salon.broadcast(ancien, "👋 #{pseudo} a quitté ##{ancien}\r\n")
      MiniDiscord.Salon.quitter(ancien, self())

      case Registry.lookup(MiniDiscord.Registry, nouveau) do
        [] ->
          DynamicSupervisor.start_child(
            MiniDiscord.SalonSupervisor,
            {MiniDiscord.Salon, nouveau}
          )

        _ -> :ok
      end

      MiniDiscord.Salon.rejoindre(nouveau, self())
      MiniDiscord.Salon.broadcast(nouveau, "📢 #{pseudo} a rejoint ##{nouveau}\r\n")
      :gen_tcp.send(socket, encrypt("Tu es dans ##{nouveau} — écris tes messages !\r\n"))
      {:continue, nouveau}
    end
  end

  defp salons_dispo do
    case MiniDiscord.Salon.lister() do
      [] -> "aucun (tu seras le premier !)"
      salons -> salons |> Enum.sort() |> Enum.join(", ")
    end
  end

  # --- chiffrement helpers ---
  defp encrypt(plain) when is_binary(plain) do
    iv = :crypto.strong_rand_bytes(16)
    cipher = :crypto.crypto_one_time(:aes_256_ctr, @key, iv, plain, true)
    iv <> cipher
  end

  defp decrypt(<<iv::binary-size(16), cipher::binary>>) do
    try do
      plain = :crypto.crypto_one_time(:aes_256_ctr, @key, iv, cipher, false)
      {:ok, plain}
    rescue
      _ -> {:error, :decrypt_failed}
    end
  end

  defp decrypt(_), do: {:error, :invalid_format}
end
