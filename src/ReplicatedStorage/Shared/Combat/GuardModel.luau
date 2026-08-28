--!strict
--[[
	Jauge de garde : absorption, rupture, régénération. Module pur (ADR-011).

	La jauge se consomme en **dégâts bruts**, pas en dégâts réduits. C'est ce qui
	rend la garde intéressante à percer : un coup lourd entame la garde à hauteur
	de ce qu'il aurait fait sans elle, donc le finisher de chaîne (14) coûte au
	défenseur presque le double d'un coup d'ouverture (8). Consommer les dégâts
	réduits rendrait la garde d'autant plus solide qu'elle protège bien, ce qui
	est exactement l'inverse de la tension recherchée.

	La rupture est un événement, pas un état : ce module dit *qu'elle a lieu*,
	c'est la couche serveur qui impose le `Stunned` correspondant. Un module pur
	ne connaît pas la machine à états.
]]

local BalanceConfig = require(script.Parent.Parent.Parent.Config.Balance)

type Balance = BalanceConfig.Balance

export type GuardState = {
	current: number,
	--[[
		Instant du dernier coup encaissé EN GARDE. Distinct du tag de combat de
		l'endurance : une garde qui se recharge parce qu'on n'a pas donné de coup
		serait absurde, seuls les coups reçus dans la garde comptent.
	]]
	lastHitAt: number,
}

local GuardModel = {}

function GuardModel.new(balance: Balance): GuardState
	return { current = balance.Block.GuardHealth, lastHitAt = 0 }
end

function GuardModel.isFull(guard: GuardState, balance: Balance): boolean
	return guard.current >= balance.Block.GuardHealth
end

--[[
	Fraction restante, pour l'affichage. Bornée à [0, 1] même si l'équilibrage
	est rechargé à chaud avec un `GuardHealth` plus bas que la valeur courante.
]]
function GuardModel.ratio(guard: GuardState, balance: Balance): number
	local maximum = balance.Block.GuardHealth
	if maximum <= 0 then
		return 0
	end
	return math.clamp(guard.current / maximum, 0, 1)
end

--[[
	Absorbe un coup. Retourne la jauge restante et si elle vient de céder.

	La rupture se déclare à zéro **atteint**, pas dépassé : un coup qui tombe
	pile sur la dernière unité de garde casse. Sans quoi la dernière unité serait
	un bouclier gratuit, et l'équilibrage de `GuardHealth` ne voudrait plus dire
	ce qu'il annonce.

	Ne mute rien : l'appelant écrit la jauge et date `lastHitAt`. Deux fonctions
	pures qui rendent des valeurs se testent en balayant les montants ; une
	fonction qui mute demanderait de reconstruire un état à chaque cas.
]]
function GuardModel.absorb(guard: GuardState, rawDamage: number): (number, boolean)
	local remaining = math.max(guard.current - rawDamage, 0)
	return remaining, remaining <= 0
end

--[[
	Fait avancer la régénération d'un pas de temps.

	Le délai court depuis le dernier coup encaissé : tenir la garde ne la
	régénère pas plus vite, la relâcher ne l'empêche pas de revenir. C'est le
	temps sans se faire toucher qui la restaure, et rien d'autre.
]]
function GuardModel.step(
	guard: GuardState,
	now: number,
	deltaTime: number,
	balance: Balance
): number
	local maximum = balance.Block.GuardHealth
	if guard.current >= maximum then
		return maximum
	end
	if now - guard.lastHitAt < balance.Block.GuardRegenDelay then
		return guard.current
	end
	return math.min(guard.current + balance.Block.GuardRegenPerSecond * deltaTime, maximum)
end

--[[
	Une garde cassée reste inutilisable tant que dure l'étourdissement, et c'est
	la machine à états qui l'interdit (aucune transition ne part de `Stunned`).
	Ce que ce module garantit, lui, c'est qu'elle repart d'une valeur pleine :
	rouvrir sur une jauge à zéro ferait re-casser au coup suivant, et le guard
	break deviendrait un verrou permanent au lieu d'une punition ponctuelle.
]]
function GuardModel.restore(balance: Balance): number
	return balance.Block.GuardHealth
end

return GuardModel
