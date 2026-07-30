--!strict
--[[
	Types du combat, partagés client et serveur.

	Note sur l'import de `Config.Balance` : il est **purement typologique**. La
	règle d'ADR-011 est qu'aucun module de combat ne *lit* la configuration au
	runtime — toutes les valeurs arrivent en argument. Importer le type de la
	table d'équilibrage ne rompt pas cette règle : les fonctions restent
	testables avec une table fabriquée, et rien n'est lu depuis Config pendant
	une frame de combat.
]]

local Balance = require(script.Parent.Parent.Parent.Config.Balance)

export type StateName =
	"Idle"
	| "Attacking"
	| "Blocking"
	| "Dashing"
	| "Stunned"
	| "Knocked"
	| "GettingUp"
	| "Downed"

export type Phase = "Windup" | "Active" | "Recovery"

--[[
	Résultat d'un coup validé. Les quatre valeurs sont figées par docs/COMBAT.md
	§5, parce que le retour visuel en deux temps du client est construit autour :
	`Ignored` couvre les i-frames, `Hit` les dégâts pleins. `Blocked` arrive avec
	la garde (tranche 1.3) et `Parried` avec la parade (tranche 1.4) ; les deux
	sont déjà dans le contrat pour que le protocole n'ait pas à changer sous les
	pieds du client à ce moment-là.
]]
export type Verdict = "Hit" | "Blocked" | "Parried" | "Ignored"

--[[
	État de combat d'un joueur. **Entièrement sérialisable** : aucune référence
	d'instance, aucune closure. C'est ce qui permet de le répliquer tel quel,
	de l'afficher dans le panneau F2, et de comparer la prédiction du client à
	l'autorité du serveur pour détecter une divergence.
]]
export type CombatState = {
	name: StateName,
	-- Tous les instants sont sur l'horloge serveur commune (Shared/Clock).
	enteredAt: number,
	-- nil quand l'état est maintenu par le joueur (Blocking) ou terminal (Downed).
	expiresAt: number?,
	-- Fin de la sous-fenêtre de l'état : parade, i-frames de dash,
	-- invulnérabilité de relevage.
	windowUntil: number?,
	-- 0 hors chaîne d'attaque.
	chainIndex: number,
	--[[
		Instant au-delà duquel la chaîne repart au premier coup.

		Posé quand un coup se résout : à `impact + ComboWindow` s'il a touché, à
		`fin du coup + WhiffResetDelay` s'il est parti dans le vide. Reste nil
		pendant le coup en cours, ce qui autorise volontairement le joueur à
		enchaîner en anticipant l'impact — c'est ce qui donne au chain sa
		fluidité au doigt sur mobile.
	]]
	chainDeadline: number?,
}

export type TransitionContext = {
	now: number,
	stamina: number,
	dashReadyAt: number,
	parryReadyAt: number,
	balance: Balance.Balance,
}

--[[
	Position et orientation d'un joueur à un instant donné. Échantillonné par
	StateService, rembobiné par Systems/Rewind pour valider les coups (Phase 1.2).
]]
export type Snapshot = {
	t: number,
	position: Vector3,
	look: Vector3,
}

return {}
