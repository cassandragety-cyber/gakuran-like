--!strict
--[[
	Structure d'un combattant. Types uniquement, aucun runtime.

	Isolé de `StateService` pour que le registre et les transitions puissent tous
	deux s'y référer sans former de cycle de require.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local RingBuffer = require(ReplicatedStorage.Shared.RingBuffer)
local StaminaModel = require(ReplicatedStorage.Shared.Combat.StaminaModel)

--[[
	Trace du dernier coup lancé, conservée même après que l'état soit revenu à
	`Idle`.

	Nécessaire parce qu'un rapport de contact arrive APRÈS le coup : à 150 ms de
	latence, l'état courant peut déjà être sorti de la phase active quand le
	rapport atteint le serveur. Valider contre l'état courant rejetterait des
	coups honnêtes ; on valide donc contre le coup tel qu'il a eu lieu.
]]
export type Swing = {
	index: number,
	startedAt: number,
}

export type Combatant = {
	model: Model,
	root: BasePart,
	-- nil pour un mannequin : rien ne le fait marcher, et exiger un `Humanoid`
	-- valide obligerait à fabriquer un rig complet pour une cible immobile.
	humanoid: Humanoid?,
	player: Player?,
	state: CombatState,
	health: number,
	maxHealth: number,
	stamina: StaminaModel.StaminaState,
	guard: number,
	dashReadyAt: number,
	parryReadyAt: number,
	sprinting: boolean,
	lastSwing: Swing?,
	-- Cibles déjà touchées par le coup en cours. Un coup ne touche jamais deux
	-- fois la même cible, quel que soit le nombre de rapports envoyés.
	swingHits: { [Model]: boolean },
	history: RingBuffer.RingBuffer<CombatTypes.Snapshot>,
	--[[
		Dernier verdict subi, pour affichage. Porté par le combattant et non
		poussé par le combat vers un afficheur : `CombatService` n'a ainsi aucune
		raison de connaître l'existence du terrain d'entraînement.
	]]
	lastVerdict: string?,
	lastDamage: number,
	lastSampleAt: number,
	lastSyncAt: number,
	dirty: boolean,
}

return {}
