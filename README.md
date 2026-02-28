# character-manager

Version: **1.0.0**

---

## 🇬🇧 English

FiveM resource to manage characters (wipe / restore) through an admin UI, compatible with QBCore, Qbox, and ESX, with optional vehicle transfer during wipe.

### Overview

- Open the UI with `/wipemenu`
- Wipe a player (delete player data)
- Restore a player from backups
- Vehicle transfer during wipe (if enabled)
- Selectable vehicle list during wipe transfer (plate, model, value)
- Vehicle decision at wipe confirmation:
	- 🟢 Transfer/Keep (both require vehicle selection)
	- 🔴 Delete (removes all vehicles)
- If Transfer is chosen:
	- Select vehicles to transfer → unselected vehicles are deleted
	- Open player search to transfer to (firstname, lastname, phone)
- If Keep is chosen:
	- Select vehicles to preserve → unselected vehicles are deleted
- If Delete is chosen:
	- All player vehicles are removed
- Admin action logging

### Wipe/Restore behavior

- Wipe is **global**: all relevant tables are handled
- During wipe transfer, only vehicles selected by admin are transferred; unselected are deleted
- During wipe keep, only vehicles selected by admin are preserved; unselected are deleted
- If vehicle action is `Delete`, all player vehicles are removed
- For `Transfer`/`Keep`, vehicle tables are excluded from the global wipe to avoid deleting kept/transferred vehicles
- `SafeWipeMode = true` (default): data is copied into `wiped_<table>`, then removed from original tables
- `SafeWipeMode = false`: data is deleted directly (no backup clone/copy in `wiped_*`)
- Restore from `wiped_<table>` is only possible when `SafeWipeMode = true`
- Excluded tables are controlled by `Config.ExcludedTables`

### Compatibility

- QBCore
- Qbox (`qbox_core`)
- ESX (`es_extended`)

### Requirements

- `oxmysql`
- **One of these frameworks:**
  - QBCore
  - Qbox (`qbox_core`)
  - ESX (`es_extended`)

### Installation

1. Put `character-manager` inside `resources`
2. Add `ensure character-manager` to `server.cfg`
3. Configure `config.lua` & `config_s.lua`
4. Restart server

### Main config (`config.lua`)

- `Language`: `en`, `fr`, `de`, `es`, `it`, `nl`, `pt`, `pt-br`, `tr`, `cs`, `da`, `sv`, `pl`, `ro`
- Note: all listed language codes are now fully translated natively.
- `Permission`: required admin group
- `VehTransfert`: enable vehicle transfer
- `SafeWipeMode`: `true` = backup then delete, `false` = direct delete (no backup)
- `EnableUpdateCheck`: check latest GitHub release on resource start (`update.lua`)
- `WebhookURL`: Discord webhook URL for logging wipe/restore actions (leave empty to disable)
- `ExcludedTables`: list of tables to exclude from wipe/restore (optional, add custom tables if needed)

### Excluded Tables Configuration

Tables in `ExcludedTables` are **skipped during wipe/restore operations**.

Additional tables can also be skipped automatically by internal patterns (ban/whitelist/log-related tables), even if they are not listed in `Config.ExcludedTables`.


**To exclude additional tables:**
1. Open `config_s.lua`
2. Add your custom table name to `ExcludedTables` list:
   ```lua
   ExcludedTables = {
       'character_manager_logs',
       'ox_lib',
       'my_custom_table',  -- Add here
       ...
   }
   ```
3. Restart the resource

**Note:** The wipe operation automatically detects and processes all player-related tables in the database. Only tables explicitly listed in `ExcludedTables` are skipped.

### Discord Webhook Logging

When a wipe or restore action is performed, a Discord embed message is automatically sent to the configured webhook (if enabled).

**Setup:**
1. Create a Discord webhook in your server channel: Settings → Integrations → Webhooks
2. Copy the webhook URL
3. Paste it in `config_s.lua` as `WebhookURL`
4. Restart the resource

**Webhook Message includes:**
- Action type (WIPE or RESTORE)
- Player name, identifier, phone, citizenid
- Admin name who performed the action
- Number of database tables modified
- Vehicle transfer status (for wipe actions)
  - If vehicles were transferred: list of transferred vehicles with plate and model
  - Target player name
  - Formatted vehicle list with plate and model
- Timestamp

To disable webhooks, leave `WebhookURL` empty.

**Example Webhook Output (Transfer):**
```
WIPE Action Logged
Player: John Doe
Identifier: license:abc123
Admin: AdminUser
Timestamp: 2026-02-17 15:30:45
Citizen ID: ABC123DEF456
Phone: 555-1234
Tables Modified: 42
Vehicles Transferred: 2
Transferred To: Jane Smith'
Vehicle List:
ABC123    | adder
DEF456    | zentorno
```

### Commands

- `/wipemenu`

### License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

### Licence

Ce projet est distribué sous licence MIT. Consulte le fichier [LICENSE](LICENSE) pour plus de détails.

---

## 🇫🇷 Français

Resource FiveM pour gérer les personnages (wipe / restore) via une UI admin, compatible QBCore, Qbox et ESX.

### Résumé

- Ouvre l’interface avec `/wipemenu`
- Wipe un joueur (suppression des données)
- Restore un joueur depuis les backups
- Transfert de véhicules lors d’un wipe (si activé)
- Liste de véhicules cochable lors du transfert (plaque, modèle, valeur)
- Choix au moment de la confirmation du wipe:
	- 🟢 Transférer/Conserver
	- 🔴 Supprimer
- Si Transférer est choisi:
	- Sélectionner les véhicules à transférer → les non-sélectionnés sont supprimés
	- Ouvre une recherche joueur pour le destinataire (prénom, nom, téléphone)
- Si Conserver est choisi:
	- Sélectionner les véhicules à conserver → les non-sélectionnés sont supprimés
- Si Supprimer est choisi:
	- Tous les véhicules du joueur sont supprimés
- Logs des actions admin

### Fonctionnement wipe/restore

- Le wipe est **global**: le script traite toutes les tables concernées
- Lors d'un transfert pendant le wipe, seuls les véhicules cochés sont transférés ; les non-cochés sont supprimés
- Lors d'une conservation pendant le wipe, seuls les véhicules cochés sont conservés ; les non-cochés sont supprimés
- Si l'action véhicule est `Supprimer`, tous les véhicules du joueur sont supprimés
- Pour `Transférer`/`Conserver`, les tables véhicules sont exclues du wipe global pour éviter de supprimer les véhicules conservés/transférés
- `SafeWipeMode = true` (défaut): les données sont copiées dans `wiped_<table>` puis supprimées des tables d’origine
- `SafeWipeMode = false`: suppression directe des données (sans clone/copie dans `wiped_*`)
- La restauration depuis `wiped_<table>` est possible uniquement si `SafeWipeMode = true`
- Les tables exclues sont définies dans `Config.ExcludedTables`

### Compatibilité

- QBCore
- Qbox (`qbox_core`)
- ESX (`es_extended`)

### Prérequis

- `oxmysql`
- **Un de ces frameworks:**
  - QBCore
  - Qbox (`qbox_core`)
  - ESX (`es_extended`)

### Installation

1. Place `character-manager` dans `resources`
2. Ajoute `ensure character-manager` dans `server.cfg`
3. Configure `config.lua` & `config_s.lua`
4. Redémarre le serveur

### Configuration principale (`config.lua`)

- `Language`: `en`, `fr`, `de`, `es`, `it`, `nl`, `pt`, `pt-br`, `tr`, `cs`, `da`, `sv`, `pl`, `ro`
- Note : tous les codes de langue listés sont désormais traduits nativement.
- `Permission`: groupe autorisé
- `VehTransfert`: active le transfert de véhicules
- `SafeWipeMode`: `true` = backup puis suppression, `false` = suppression directe (sans backup)
- `EnableUpdateCheck`: vérifie la dernière release GitHub au démarrage (`update.lua`)
- `ExcludedTables`: liste des tables à exclure du wipe/restore (optionnel, ajoute manuellement si nécessaire)

### Configuration des tables exclues

Les tables listées dans `ExcludedTables` sont **ignorées lors des opérations wipe/restore**.

D'autres tables peuvent aussi etre ignorees automatiquement via les motifs internes (tables de ban/whitelist/log), meme si elles ne sont pas listees dans `Config.ExcludedTables`.


**Pour exclure des tables supplémentaires:**
1. Ouvre `config_s.lua`
2. Ajoute le nom de ta table personnalisée à la liste `ExcludedTables`:
   ```lua
   ExcludedTables = {
       'character_manager_logs',
       'ox_lib',
       'ma_table_personalisee',  -- Ajoute ici
       ...
   }
   ```
3. Redémarre la ressource

**Note:** L'opération wipe détecte et traite automatiquement toutes les tables liées aux joueurs dans la base de données. Seules les tables explicitement listées dans `ExcludedTables` sont ignorées.

### Webhooks Discord

Quand une action wipe ou restore est effectuée, un message embed Discord est automatiquement envoyé au webhook configuré (si activé).

**Configuration:**
1. Crée un webhook Discord dans ton canal serveur : Settings → Integrations → Webhooks
2. Copie l'URL du webhook
3. Colle-la dans `config_s.lua` comme `WebhookURL`
4. Redémarre la ressource

**Le message webhook contient:**
- Type d'action (WIPE ou RESTORE)
- Nom du joueur, identifiant, téléphone, citizenid
- Nom de l'admin qui a effectué l'action
- Nombre de tables de base de données modifiées
- Statut du transfert de véhicules (pour les actions wipe)
  - Si des véhicules ont été transférés: liste des véhicules avec plaque et modèle
  - Nom du joueur destinataire
  - Liste formatée des véhicules (plaque et modèle)
- Timestamp

Pour désactiver les webhooks, laisse `WebhookURL` vide.

**Exemple de sortie webhook (Transfert):**
```
WIPE Action Logged
Joueur: John Doe
Identifiant: license:abc123
Admin: AdminUser
Timestamp: 2026-02-17 15:30:45
Citizen ID: ABC123DEF456
Téléphone: 555-1234
Tables modifiées: 42
Véhicules transférés: 2
Transférés vers: Jane Smith
Liste des véhicules:
ABC123    | adder
DEF456    | zentorno
```

### Commandes

- `/wipemenu`