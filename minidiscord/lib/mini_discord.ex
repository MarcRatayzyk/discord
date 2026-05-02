defmodule MiniDiscord do
  # point d'entrée otp au démarrage
  use Application

  def start(_type, _args) do
    # pseudos occupés : clé = pseudo, valeur = pid du handler
    :ets.new(:pseudos, [:named_table, :public, :set])

    children = [
      # trouve un salon par son nom (clé unique)
      {Registry, keys: :unique, name: MiniDiscord.Registry},
      # crée les processus Salon à la demande
      {DynamicSupervisor, strategy: :one_for_one, name: MiniDiscord.SalonSupervisor},
      # écoute tcp port 4040
      MiniDiscord.ChatServer,
      # une task par client connecté
      {Task.Supervisor, name: MiniDiscord.TaskSupervisor}
    ]

    # si un enfant crash : seulement lui redémarre (one_for_one)
    opts = [strategy: :one_for_one, name: MiniDiscord.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
