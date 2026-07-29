--!strict
--[[
	Types partagés client/serveur.

	Ce module n'exporte AUCUN runtime : il ne contient que des définitions de
	types. On le require uniquement pour ses types :
		local Types = require(...Shared.Types)
		local spec: Types.SkillSpec = ...

	Règle : un type qui traverse le réseau vit ici et nulle part ailleurs, pour
	que le contrat soit lisible d'un seul endroit (cf. docs/THREAT_MODEL.md).
]]

-- ==========================================================================
-- Personnage et progression
-- ==========================================================================

export type StatName = "Force" | "Vitesse" | "Endurance" | "Resistance"

export type StatBlock = {
	Force: number,
	Vitesse: number,
	Endurance: number,
	Resistance: number,
}

-- ==========================================================================
-- Styles de combat
-- ==========================================================================

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Mythic"

export type SkillSlot = "M1" | "Z" | "X" | "C" | "V"

export type HitboxShape = "Box" | "Sphere"

export type HitboxSpec = {
	shape: HitboxShape,
	-- Pour "Sphere", seule la composante X est lue (rayon).
	size: Vector3,
	-- Décalage relatif au HumanoidRootPart de l'attaquant, orienté vers l'avant.
	offset: CFrame,
	maxTargets: number,
}

--[[
	La grammaire d'effets (ADR-003). CombatService interprète ces variantes et
	rien d'autre : un style est de la donnée, jamais du code.
]]
export type EffectSpec =
	{ kind: "Damage", amount: number, poise: number, hitstop: number }
	| { kind: "Knockback", speed: number, vertical: number }
	| { kind: "Knockdown", ragdollTime: number }
	| { kind: "Stun", duration: number }
	| { kind: "Status", id: string, duration: number, stacks: number }
	| { kind: "Move", distance: number, iframes: number }
	| { kind: "Heal", amount: number }

export type SkillSpec = {
	id: string,
	slot: SkillSlot,
	-- Phases, en secondes. La hitbox s'ouvre à `windup` et se ferme à
	-- `windup + active`. La durée totale de l'animation vaut la somme des trois
	-- (c'est la règle que docs/ANIMATIONS.md donne à l'animateur).
	windup: number,
	active: number,
	recovery: number,
	cooldown: number,
	staminaCost: number,
	hitbox: HitboxSpec?,
	onCast: { EffectSpec },
	onHit: { EffectSpec },
	-- Si vrai, la phase de recovery peut être annulée par un dash.
	cancelable: boolean,
	-- Clé dans Config/Animations, pas un asset id : voir ADR-009.
	anim: string,
	vfx: string?,
	sfx: string?,
}

export type StyleDef = {
	id: string,
	name: string,
	rarity: Rarity,
	weight: number,
	statMods: StatBlock,
	skills: { SkillSpec },
	animPack: string,
}

-- ==========================================================================
-- Payloads réseau
--
-- Aucun de ces types ne contient de dégât, de montant ni d'identifiant d'item
-- choisi librement par le client : le client décrit une INTENTION, le serveur
-- décide du résultat.
-- ==========================================================================

export type PingRequest = {
	seq: number,
	-- Horodatage `Clock.now()` au moment de l'envoi, utilisé pour mesurer la
	-- dérive d'horloge client/serveur (base de la lag comp, ADR-001).
	clientTime: number,
}

export type PingReply = {
	seq: number,
	serverTime: number,
}

return {}
