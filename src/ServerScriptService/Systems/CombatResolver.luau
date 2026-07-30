--!strict
--[[
	L'arbitre : que produit un coup validé sur un défenseur donné ?

	Module pur, et c'est ici que se gagnera l'irréprochabilité de la parade
	(tranche 1.4). `resolve` est une fonction de (frame data, état du défenseur,
	instant, équilibrage) vers un verdict : on peut donc balayer l'instant
	d'impact milliseconde par milliseconde autour d'une fenêtre et vérifier que la
	frontière tombe exactement où elle doit, sans partie lancée, sans réseau, sans
	deux clients.

	État d'avancement des branches, volontairement explicite :
	  - `Ignored` et `Hit` : livrés (tranche 1.2).
	  - `Blocked`  : tranche 1.3, avec la jauge de garde.
	  - `Parried`  : tranche 1.4.
	Le type `Verdict` porte déjà les quatre valeurs (docs/COMBAT.md §5) pour que
	le protocole réseau ne change pas sous les pieds du client à ce moment-là.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)

type Balance = BalanceConfig.Balance

export type DefenderView = {
	state: CombatTypes.CombatState,
	guard: number,
	health: number,
}

export type Outcome = {
	verdict: CombatTypes.Verdict,
	damage: number,
	-- Points de poise retirés. Sert à la tranche 1.3 pour casser une garde.
	poise: number,
	knockdown: boolean,
	-- Durée du figement à l'impact, jouée par le client.
	hitstop: number,
	guardRemaining: number,
}

local CombatResolver = {}

local function ignored(defender: DefenderView): Outcome
	return {
		verdict = "Ignored",
		damage = 0,
		poise = 0,
		knockdown = false,
		hitstop = 0,
		guardRemaining = defender.guard,
	}
end

--[[
	Applique un coup à un défenseur.

	`step` est le frame data du coup porté, pas un montant envoyé par le client :
	le serveur l'a résolu depuis l'index de chaîne qu'il détient (ADR-012).
]]
function CombatResolver.resolve(
	step: BalanceConfig.MeleeStep,
	defender: DefenderView,
	now: number,
	_balance: Balance
): Outcome
	-- Un combattant déjà à terre n'encaisse rien de plus : sans ça, une chaîne
	-- lancée sur un adversaire en train de tomber le tuerait pendant qu'il est
	-- injouable.
	if defender.state.name == "Downed" then
		return ignored(defender)
	end

	-- I-frames de dash et invulnérabilité de relevage. La machine à états en est
	-- seule juge, pour que la règle soit la même que celle que le client prédit.
	if StateMachine.isInvulnerable(defender.state, now) then
		return ignored(defender)
	end

	return {
		verdict = "Hit",
		damage = step.damage,
		poise = step.poise,
		knockdown = step.knockdown,
		hitstop = step.hitstop,
		guardRemaining = defender.guard,
	}
end

return CombatResolver
