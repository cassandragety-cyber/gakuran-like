--!strict
--[[
	Endurance : consommation et régénération. Module pur (ADR-011).

	Le tag de combat conditionne la vitesse de régénération. Il est posé par le
	serveur à chaque coup donné ou reçu ; ici on ne fait que lire son échéance.
	C'est ce qui produit le rythme voulu par le brief : on ne récupère
	vraiment qu'en sortant de l'échange.
]]

local BalanceConfig = require(script.Parent.Parent.Parent.Config.Balance)

type Balance = BalanceConfig.Balance

export type StaminaState = {
	current: number,
	-- Instant du dernier coup donné ou reçu. Le tag est actif jusqu'à
	-- `lastCombatAt + CombatTagDuration`.
	lastCombatAt: number,
}

local StaminaModel = {}

function StaminaModel.isInCombat(stamina: StaminaState, now: number, balance: Balance): boolean
	return now - stamina.lastCombatAt < balance.Stamina.CombatTagDuration
end

function StaminaModel.regenRate(stamina: StaminaState, now: number, balance: Balance): number
	return if StaminaModel.isInCombat(stamina, now, balance)
		then balance.Stamina.RegenInCombat
		else balance.Stamina.RegenOutOfCombat
end

--[[
	Fait avancer l'endurance d'un pas de temps.

	Dépenser et récupérer sont **exclusifs** : tant qu'une dépense continue est en
	cours (le sprint), la régénération est suspendue. Additionner les deux serait
	non seulement contradictoire, ce serait faux — la régénération hors combat
	(22/s) dépasse le coût du sprint (8/s), donc courir rechargerait l'endurance
	au lieu de la consommer, et le sprint deviendrait gratuit. Le brief demande
	l'inverse.
]]
function StaminaModel.step(
	stamina: StaminaState,
	now: number,
	deltaTime: number,
	drainPerSecond: number,
	balance: Balance
): number
	local rate = if drainPerSecond > 0
		then -drainPerSecond
		else StaminaModel.regenRate(stamina, now, balance)
	return math.clamp(stamina.current + rate * deltaTime, 0, balance.Stamina.Max)
end

function StaminaModel.canAfford(stamina: StaminaState, cost: number): boolean
	return stamina.current >= cost
end

function StaminaModel.spend(stamina: StaminaState, cost: number): number
	return math.max(stamina.current - cost, 0)
end

--[[
	Le sprint s'arrête de lui-même sous le seuil d'action. Sans ça, un joueur
	pourrait sprinter à endurance nulle et arriver au combat sans rien pour
	dasher ni garder — le coût cesserait d'être un choix.
]]
function StaminaModel.canSprint(stamina: StaminaState, balance: Balance): boolean
	return stamina.current > balance.Stamina.MinimumToAct
end

return StaminaModel
