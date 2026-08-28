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

local CombatTypes = require(script.Parent.Combat.Types)

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

--[[
	État autoritatif d'un joueur, poussé par le serveur. Contient tout ce dont le
	client a besoin pour afficher et, à partir de la tranche 1.2, réconcilier sa
	prédiction.
]]
export type StateSync = {
	userId: number,
	state: CombatTypes.CombatState,
	health: number,
	stamina: number,
	guard: number,
	--[[
		Les cooldowns font partie de l'état répliqué, pas du confort d'affichage :
		sans eux le client ne peut pas prédire un refus de dash ou de garde, et
		afficherait une action possible que le serveur va rejeter.
	]]
	dashReadyAt: number,
	parryReadyAt: number,
}

--[[
	Intention de sprint. Le client n'annonce ni sa vitesse ni sa position : le
	serveur reste seul à écrire `WalkSpeed` et seul à décider si l'endurance
	permet encore de courir.
]]
export type SprintIntent = {
	active: boolean,
	clientTime: number,
}

--[[
	Intention d'attaquer. Ne contient PAS l'index de chaîne : le serveur le dérive
	de l'état qu'il détient, sans quoi un client réclamerait le coup final et son
	knockdown à la demande (ADR-012).
]]
export type AttackIntent = {
	seq: number,
	clientTime: number,
}

--[[
	Ouverture ou fermeture de la garde. **Il n'existe pas de message « j'ai
	paré »** : le client décrit l'instant où il a levé la garde, le serveur seul
	décide si un coup tombe dans la fenêtre (ADR-002, COMBAT.md §4). C'est la
	différence entre déclarer une intention et réclamer un résultat, et c'est ce
	qui rend la parade non triviale à tricher.

	`clientTime` est l'instant de l'appui sur l'horloge commune. Il ancre la
	fenêtre de parade, jamais le cooldown qui la gouverne (ADR-017).
]]
export type BlockIntent = {
	open: boolean,
	clientTime: number,
}

--[[
	Contacts détectés localement par le client.

	Les cibles sont des `Instance` : un mannequin d'entraînement n'est pas un
	`Player`, et le serveur a de toute façon besoin de vérifier chaque référence
	contre son registre de combattants. Aucun dégât, aucune distance, aucun
	verdict ne transite ici — seulement « je pense avoir touché ceux-là, à cet
	instant ».
]]
export type HitReport = {
	seq: number,
	clientTime: number,
	targets: { Instance },
}

--[[
	Verdict d'un coup, calculé par le serveur. Envoyé à l'attaquant et, si la
	cible est un joueur, à elle aussi.
]]
export type HitResult = {
	seq: number,
	verdict: CombatTypes.Verdict,
	damage: number,
	target: Instance,
	targetHealth: number,
	hitstop: number,
	--[[
		La garde du défenseur a-t-elle cédé sur ce coup ? Le verdict reste
		`Blocked` : c'est un effet de bord du blocage, pas un cinquième verdict.

		Les deux camps en ont besoin pour jouer la bonne chose — le défenseur une
		rupture de garde plutôt qu'un simple encaissement, l'attaquant le signal
		qu'une ouverture d'1,6 s vient de s'ouvrir. N'apprend rien qu'ils ne
		puissent déjà voir à l'écran.
	]]
	guardBroken: boolean,
}

--[[
	Refus d'une demande, avec son code. Le client s'en sert pour expliquer plutôt
	que de laisser croire à un coup perdu — un joueur qui frappe à travers un mur
	doit savoir pourquoi rien ne s'est passé.
]]
export type Refusal = {
	seq: number,
	code: string,
}

--[[
	Réglage à chaud d'une valeur d'équilibrage. `path` est vérifié contre la liste
	blanche de `Config/Debug`, jamais interprété directement (ADR-013).
]]
export type TuningChange = {
	path: string,
	value: number,
}

return {}
