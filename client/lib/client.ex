defmodule MiniDiscord.Client do

  @doc """
  Valide un message avant envoi ou réception.
  Retourne {:ok, msg} si le message est valide
  Retourne {:error, raison} sinon
  """
    # Clé partagée (32 octets hex). Remplacez par une clé secrète partagée.
    @key Base.decode16!("00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF", case: :mixed)
  def valider_message(msg) do
    msg = String.trim(msg)

    cond do
      msg == "" ->#message vide
        {:error, "Message vide"}

      String.length(msg) > 500 ->#si message trop long
        {:error, "Message trop long (max 500 chars)"}

      String.contains?(msg, ["<", ">", "?", "\\", "\0"]) -># si message contient des caractères interdits
        {:error, "Message contient des caractères non autorisés"}

      true ->
        {:ok, msg}
    end
  end

  @doc """
  Point d'entrée principal du client.
  host : nom type 'xxxbore.pub'
  port : entier ex: 4040
  """
  def start(host, port) do
    connect_with_retry(host, port,1)
  end
#fonction de connexion avec retry en cas d'échec pour reconnexion automatique
defp connect_with_retry(host,port,attempt) do
  host = if is_binary(host), do: String.to_charlist(host), else: host
  case :gen_tcp.connect(host, port, [:binary,packet: :line, active: false]) do
    {:ok, socket } ->
      connect_loop(host,port,socket)#si ok on entre dans la boucle de communication avec le serveur
    {:error, reason} ->
      IO.puts("Tentative de connexion #{attempt} échouée: #{reason}")
      :timer.sleep(2000) # Attendre 2 secondes avant de réessayer
      connect_with_retry(host, port, attempt + 1)
  end
end

defp connect_loop(host,port,socket) do
  rencontre(socket)#permet de faire la rencontre avec le serveur pour choisir le pseudo et le salon
  recv_task = Task.async(fn -> receive_loop(socket,host,port) end)
  send_task = Task.async(fn -> send_loop(socket) end)
  Task.await(recv_task, :infinity)
  Task.await(send_task, :infinity)
  IO.puts("Déconnecté")
  connect_with_retry(host,port,1) # Reconnecter après la déconnexion
end




  defp recv_print(socket) do
      # on reçoit un binaire chiffré : <<iv::16, cipher::binary>>
      case :gen_tcp.recv(socket, 0) do
        {:ok, bin} ->
          case decrypt(bin) do
            {:ok, plain} -> IO.write(plain)
            {:error, _} -> IO.puts("Message illisible")
          end
        {:error, _} -> IO.puts("Déconnecté")
      end
  end

  defp rencontre(socket) do
     recv_print(socket) # lire et déchiffrer le message serveur
     pseudo = IO.gets("Entrez votre pseudo: ")
     :ok = :gen_tcp.send(socket, encrypt(pseudo)) # envoi chiffré
     recv_print(socket)
     salons = IO.gets("Entrez le nom du salon: ")
     :ok = :gen_tcp.send(socket, encrypt(salons)) # envoi chiffré
     recv_print(socket)
  end

  defp receive_loop(socket, host, port) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, bin} ->#  on reçoit un message du serveur
        case decrypt(bin) do#on déchiffre le message reçu
          {:ok, plain} -> IO.write(plain)
          {:error, _} -> IO.puts("Message illisible")
        end
        receive_loop(socket, host, port)

      {:error, reason} ->
        IO.puts("\nConnexion perdue (#{inspect(reason)}). Reconnexion...")
        :gen_tcp.close(socket)
        connect_with_retry(host, port, 1)
    end
  end

  defp send_loop(socket) do
    case IO.gets("Entrez votre message: ") do
      nil -> # EOF
        :closed

      ligne ->
        case valider_message(ligne) do
          {:ok, msg_valide} ->
            # on chiffre le message avant envoi
            bin = encrypt(msg_valide <> "\r\n")
            case :gen_tcp.send(socket, bin) do
              :ok -> send_loop(socket)
              {:error, _reason} -> IO.puts("Déconnecté"); :closed
            end

          {:error, raison} -> IO.puts("❌ #{raison}"); send_loop(socket)
        end
    end
  end

  # fonction de chiffrement
  defp encrypt(plain) when is_binary(plain) do
    iv = :crypto.strong_rand_bytes(16)#creer un iv aléatoire de 16 octets
    cipher = :crypto.crypto_one_time(:aes_256_ctr, @key, iv, plain, true)#chiffre le message en utilisant AES-256-CTR avec la clé partagée et l'iv
    iv <> cipher#concatène l'iv et le message chiffré pour l'envoi
  end
 #fonction de dechiffremnt
  defp decrypt(<<iv::binary-size(16), cipher::binary>>) do#iv::binary-size(16) pour extraire les 16 premiers octets comme iv et le reste comme cipher
    try do
      plain = :crypto.crypto_one_time(:aes_256_ctr, @key, iv, cipher, false)#dechiffre le message en utilisant AES-256-CTR avec la clé partagée et l'iv
      {:ok, plain}
    rescue
      _ -> {:error, :decrypt_failed}
    end
  end

  defp decrypt(_), do: {:error, :invalid_format}

end
