--!strict
--[[
	Noms de DataStore et de MemoryStore.

	Contrainte figée avec le produit : le nom d'affichage du jeu sur Roblox peut
	changer, les clés de stockage non. Elles sont donc préfixées `Banchou_` et
	suffixées par une version de schéma explicite. Renommer un DataStore après
	lancement = repartir de zéro pour tous les joueurs ; changer le suffixe de
	version est au contraire une opération volontaire, accompagnée d'une
	migration dans Systems/SchemaMigrations (Phase 2).

	Config.validate() impose le format `Banchou_<Nom>_v<N>` au boot.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

local DataStores = {
	PlayerData = "Banchou_PlayerData_v1",
	GangData = "Banchou_GangData_v1",

	-- MemoryStore pour le partage cross-server léger des gangs (Phase 5).
	GangPresenceMap = "Banchou_GangPresence_v1",

	-- Version du schéma de profil effectivement écrite dans les données. Elle
	-- est indépendante du suffixe de clé : on peut migrer v1 -> v2 à l'intérieur
	-- du même DataStore tant que la migration est réversible en lecture.
	ProfileSchemaVersion = 1,
}

return TableUtil.deepFreeze(DataStores)
