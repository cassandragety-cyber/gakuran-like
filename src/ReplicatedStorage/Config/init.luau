--!strict
--[[
	Point d'entrée unique de la configuration.

	Ce module n'est qu'un agrégateur : il ne contient aucune logique, y compris
	pas la validation (qui vit dans Systems/ConfigValidator, côté serveur, parce
	que c'est du code testable et non de la donnée).

	Deux façons d'accéder à la config, au choix selon le besoin de typage :
		local Config = require(ReplicatedStorage.Config)
		Config.Balance.Parry.Window
	ou, quand on ne veut qu'une table :
		local Balance = require(ReplicatedStorage.Config.Balance)
]]

local Animations = require(script.Animations)
local Balance = require(script.Balance)
local DataStores = require(script.DataStores)
local Monetization = require(script.Monetization)
local Rarity = require(script.Styles.Rarity)
local RateLimits = require(script.RateLimits)
local TableUtil = require(script.Parent.Shared.TableUtil)

local Config = {
	Animations = Animations,
	Balance = Balance,
	DataStores = DataStores,
	Monetization = Monetization,
	RateLimits = RateLimits,
	Rarity = Rarity,
}

return TableUtil.deepFreeze(Config)
