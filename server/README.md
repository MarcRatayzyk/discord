# discord

Q1. Pourquoi utilise-t-on Process.monitor/1 dans handle_call({:rejoindre}) ? 

R1.Process.monitor/1 surveille le processeur du client. Si le client il crash ou ferme sa connexion, le salon reçois un message {:DOWN, ...} pour savoir que le client s'est deconnecté. On peut donc facilement le retirer de la liste.

Q2. Que se passe-t-il si on n'implémente pas handle_info({:DOWN, ...}) ? 

R2. Si on implémente pas handle_info({:DOWN, ...}), les clients mort resterait dans la liste des clients. Après quand on fait un broadcast, on essai d'envoyer un msg à un processeurs qui existe plus donc le message est perdu.

Q3. Quelle est la différence entre handle_call et handle_cast ? Pourquoi broadcast est un cast ?

R3.Handle_call attend une reponse (c'est synchrone), handle_cast attend rien c'est asynchrone. On utilise cast pour broadcast car on veux juste envoyer les messages sans attendre le client . C'est plus rapide et on a pas besoin de reponse.

2-4. Le salon redémarre-t-il après le kill ? Pourquoi ? 

R2-4. Oui, le salon redémarre si son superviseur utilise une stratégie et une politique de redémarrage actives. Quand le processus du salon est tué, le superviseur détecte l'arrêt et le relance automatiquement selon sa configuration. Cela garantit la résilience du système : même si un salon crash, il sera restauré.

2-5. Quelle est la différence entre les stratégies :one_for_one et :one_for_all ?

R2-5. Avec :one_for_one, seul le processus qui plante est redémarré. Avec :one_for_all, si un processus plante, tous les processus enfants du superviseur sont arrêtés puis redémarrés ensemble. :one_for_one est moins radical et préserve les autres services, tandis que :one_for_all redémarre tout pour garantir une cohérence totale.


Chiffrement AES-256-CTR : le handler déchiffre les paquets entrants, valide le texte en clair, diffuse/stocke en clair et chiffre les envois par client via `@key`, `encrypt/1` et `decrypt/1` (clé codée en dur pour la démo — externaliser en production).(aide d'ia pour faire les handlers et l'implementation du chiffrement)


