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
	  - `Ignored`, `Hit` : livrés (tranche 1.2).
	  - `Blocked` : livré (tranche 1.3), avec la jauge de garde.
	  - `Parried` : tranche 1.4.
	Le type `Verdict` porte déjà les quatre valeurs (docs/COMBAT.md §5) pour que
	le protocole réseau ne change pas sous les pieds du client à ce moment-là.

	**Ordre des branches, et il est intentionnel.** La parade s'insérera en 1.4
	AVANT le blocage, à l'intérieur du même test « le défenseur garde-t-il ? » :
	parer est un blocage dont l'instant tombe dans la fenêtre. Écrire le blocage
	comme une branche à part entière aujourd'hui, plutôt que comme un `else` de
	la parade, évite d'avoir à réécrire la structure en 1.4.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local GuardModel = require(ReplicatedStorage.Shared.Combat.GuardModel)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)

type Balance = BalanceConfig.Balance

export type DefenderView = {
	state: CombatTypes.CombatState,
	guard: GuardModel.GuardState,
	health: number,
}

export type Outcome = {
	verdict: CombatTypes.Verdict,
	damage: number,
	-- Points de poise retirés. Réservé aux compétences de style (Phase 2) : le
	-- chain M1 casse la garde par la jauge, pas par le poise.
	poise: number,
	knockdown: boolean,
	-- Durée du figement à l'impact, jouée par le client.
	hitstop: number,
	guardRemaining: number,
	--[[
		La garde vient-elle de céder sur ce coup ? Le verdict reste `Blocked` — le
		coup a bien été bloqué, c'est la garde qui ne survit pas. Séparer les deux
		évite un cinquième verdict que le client devrait apprendre, alors qu'il
		s'agit d'un effet de bord du blocage.
	]]
	guardBroken: boolean,
}

local CombatResolver = {}

local function ignored(defender: DefenderView): Outcome
	return {
		verdict = "Ignored",
		damage = 0,
		poise = 0,
		knockdown = false,
		hitstop = 0,
		guardRemaining = defender.guard.current,
		guardBroken = false,
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
	balance: Balance
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

	if defender.state.name == "Blocking" then
		-- Tranche 1.4 : la parade s'insère ICI, avant le blocage — un coup dont
		-- l'instant tombe dans `[ouverture, ouverture + Parry.Window]` est paré,
		-- les autres sont bloqués.
		return CombatResolver.blocked(step, defender, balance)
	end

	return {
		verdict = "Hit",
		damage = step.damage,
		poise = step.poise,
		knockdown = step.knockdown,
		hitstop = step.hitstop,
		guardRemaining = defender.guard.current,
		guardBroken = false,
	}
end

--[[
	Coup encaissé en garde.

	La jauge se consomme en dégâts **bruts** (`step.damage`) alors que la vie ne
	prend que la fraction réduite : garder coûte donc cher contre un coup lourd,
	ce qui est ce qui rend le finisher de chaîne menaçant même face à une garde.

	Le coup qui casse la garde inflige quand même des dégâts **réduits**, pas
	pleins. La punition du guard break est l'étourdissement de 1,6 s — largement
	de quoi placer une chaîne complète. Y ajouter les dégâts pleins ferait payer
	deux fois la même faute, et rendrait la garde plus dangereuse que ne pas
	garder du tout, ce qui n'a aucun sens à apprendre pour un joueur.
]]
function CombatResolver.blocked(
	step: BalanceConfig.MeleeStep,
	defender: DefenderView,
	balance: Balance
): Outcome
	local remaining, broken = GuardModel.absorb(defender.guard, step.damage)

	return {
		verdict = "Blocked",
		damage = step.damage * balance.Block.DamageMultiplier,
		poise = step.poise,
		-- Un coup bloqué n'envoie jamais au sol, même le finisher : la garde a
		-- fait son travail. Le knockdown revient par le guard break, sous forme
		-- d'étourdissement, et c'est la couche serveur qui l'impose.
		knockdown = false,
		hitstop = step.hitstop,
		guardRemaining = remaining,
		guardBroken = broken,
	}
end

return CombatResolver
