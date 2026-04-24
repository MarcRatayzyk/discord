# discord

Q1. Pourquoi utilise-t-on Process.monitor/1 dans handle_call({:rejoindre}) ? 

R1. Process.monitor/1 surveille le processus du client. Si le client crash ou ferme sa connexion, le salon reçoit un message {:DOWN, ...} pour savoir que le client s'est déconnecté. Comme ça on peut le retirer automatiquement de la liste.

Q2. Que se passe-t-il si on n'implémente pas handle_info({:DOWN, ...}) ? 

R2. Si on n'implémente pas handle_info({:DOWN, ...}), les clients morts resteraient dans la liste des clients. Ensuite, quand on fait un broadcast, on essaie d'envoyer un message à un processus qui n'existe plus, donc le message est perdu.

Q3. Quelle est la différence entre handle_call et handle_cast ? Pourquoi broadcast est un cast ?

R3. handle_call attend une réponse (synchrone), alors que handle_cast ne l'attend pas (asynchrone). On utilise cast pour broadcast parce qu'on veut juste envoyer les messages sans attendre que les clients reçoivent. C'est plus rapide et on n'a pas besoin d'une réponse.

Phase 2. Questions
2-4. Le salon redémarre-t-il après le kill ? Pourquoi ? 

R2-4. Oui, le salon redémarre si son superviseur utilise une stratégie et une politique de redémarrage actives. Quand le processus du salon est tué, le superviseur détecte l'arrêt et le relance automatiquement selon sa configuration.

2-5. Quelle est la différence entre les stratégies :one_for_one et :one_for_all ?

R2-5. Avec :one_for_one, seul le processus qui plante est redémarré. Avec :one_for_all, si un processus plante, tous les processus enfants du superviseur sont arrêtés puis redémarrés ensemble.
