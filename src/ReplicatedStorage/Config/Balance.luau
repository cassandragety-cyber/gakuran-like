--!strict
--[[
	Équilibrage global du combat. DONNÉE PURE — aucune fonction, aucune logique.

	Règle d'or du projet : rééquilibrer le jeu ne doit jamais demander d'ouvrir
	un script de gameplay. Si une valeur numérique de combat apparaît ailleurs
	que dans Config/, c'est un bug.

	Les durées sont en secondes, les distances en studs, les dégâts en points de
	vie sur une base de 100 PV. docs/ANIMATIONS.md dérive directement de la
	table `Melee` ci-dessous : modifier une durée ici invalide l'animation
	correspondante, il faut mettre le document à jour dans le même commit.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

export type MeleeStep = {
	windup: number,
	active: number,
	recovery: number,
	damage: number,
	-- Dégâts de poise infligés : casse l'armure d'un adversaire en pleine
	-- animation. Le poise du défenseur vit dans Balance.Combat.BasePoise.
	poise: number,
	hitstop: number,
	knockbackSpeed: number,
	-- Le dernier coup de la chaîne envoie au sol (brief §5.1).
	knockdown: boolean,
	-- Si vrai, la récupération peut être annulée par un dash. Le coup final ne
	-- l'est pas : sa longue récupération est la contrepartie du knockdown.
	cancelable: boolean,
}

local Balance = {
	Character = {
		MaxHealth = 100,
		WalkSpeed = 16,
		SprintSpeed = 24,
		JumpPower = 50,
	},

	Stamina = {
		Max = 100,
		-- Régen bridée tant que le tag de combat est actif : le brief demande
		-- explicitement une régen plus rapide hors combat.
		RegenInCombat = 6,
		RegenOutOfCombat = 22,
		-- Délai après le dernier coup donné ou reçu avant de repasser « hors
		-- combat ».
		CombatTagDuration = 4,
		SprintDrainPerSecond = 8,
		-- En dessous de ce seuil, sprint et dash sont refusés (pas de dash à
		-- 1 point d'endurance qui laisse sans ressource).
		MinimumToAct = 10,
	},

	Combat = {
		BasePoise = 30,
		-- Fenêtre pendant laquelle le coup suivant du chain reste enchaînable,
		-- décomptée à partir de l'impact du coup précédent (brief §5.1).
		ComboWindow = 0.55,
		DefaultChainLength = 4,
		-- Un style peut définir jusqu'à 5 coups ; au-delà, Config.validate rejette.
		MaxChainLength = 5,
		-- Temps avant que la chaîne ne reparte à zéro après un coup dans le vide.
		WhiffResetDelay = 0.8,
	},

	--[[
		Frame data du chain M1 par défaut. Un style peut fournir sa propre table,
		celle-ci sert de référence d'équilibrage et de gabarit d'animation.

		Lecture d'une ligne : l'animation dure windup + active + recovery ;
		l'impact tombe exactement à `windup`.

		Toutes les durées de phase sont des multiples de 0.05 s, soit 3 frames
		à 60 fps : l'animateur travaille alors sur des frames entières, sans
		clé posée entre deux images.
	]]
	Melee = {
		{
			windup = 0.10,
			active = 0.10,
			recovery = 0.25,
			damage = 8,
			poise = 10,
			hitstop = 0.05,
			knockbackSpeed = 6,
			knockdown = false,
			cancelable = true,
		} :: MeleeStep,
		{
			windup = 0.10,
			active = 0.10,
			recovery = 0.25,
			damage = 8,
			poise = 10,
			hitstop = 0.05,
			knockbackSpeed = 6,
			knockdown = false,
			cancelable = true,
		} :: MeleeStep,
		{
			windup = 0.15,
			active = 0.10,
			recovery = 0.30,
			damage = 9,
			poise = 14,
			hitstop = 0.06,
			knockbackSpeed = 9,
			knockdown = false,
			cancelable = true,
		} :: MeleeStep,
		{
			windup = 0.20,
			active = 0.15,
			recovery = 0.40,
			damage = 14,
			poise = 30,
			hitstop = 0.08,
			knockbackSpeed = 14,
			knockdown = true,
			cancelable = false,
		} :: MeleeStep,
	},

	Hitbox = {
		-- Boîte du M1 : large en X pour pardonner l'imprécision au doigt sur
		-- mobile, courte en Z pour que la portée reste lisible.
		MeleeSize = Vector3.new(5, 5, 7),
		MeleeOffset = CFrame.new(0, 0, -3.5),
		MaxTargetsPerSwing = 3,
		-- Marge ajoutée à la portée lors de la revalidation serveur, pour
		-- absorber l'interpolation. Au-delà, le hit est rejeté.
		ServerToleranceStuds = 2.5,
		-- Le défenseur doit être devant l'attaquant : cos de l'angle maximum.
		-- 0.35 ≈ un cône de 140° au total.
		FacingDot = 0.35,
	},

	Block = {
		DamageMultiplier = 0.35,
		-- Points de dégâts bruts absorbables avant guard break.
		GuardHealth = 60,
		GuardRegenPerSecond = 12,
		GuardRegenDelay = 1.5,
		GuardBreakStun = 1.6,
		-- Un joueur en garde se déplace lentement, il ne peut pas kite gratuitement.
		WalkSpeedMultiplier = 0.55,
	},

	Parry = {
		-- Fenêtre à l'activation de la garde (brief §5.1).
		Window = 0.20,
		-- Stun renvoyé à l'attaquant.
		AttackerStun = 1.2,
		-- Le défenseur récupère aussi de l'endurance : le parry doit être
		-- récompensé, pas seulement non puni.
		StaminaReward = 15,
		Hitstop = 0.08,
		-- Délai avant de pouvoir réouvrir une fenêtre de parry, pour empêcher
		-- le maintien-relâche en boucle.
		Cooldown = 0.55,
	},

	Dash = {
		Distance = 14,
		Duration = 0.20,
		-- I-frames courtes : elles commencent au départ du dash, pas avant.
		InvulnerabilityDuration = 0.12,
		Cooldown = 1.2,
		StaminaCost = 18,
		DoubleTapWindow = 0.28,
	},

	Knockdown = {
		RagdollDuration = 1.1,
		GetUpDuration = 0.6,
		-- Invulnérabilité au relevage, pour éviter le viol de knockdown infini.
		GetUpInvulnerability = 0.35,
	},

	Network = {
		-- ADR-001 : borne du rembobinage. Au-delà, le hit est rejeté même si le
		-- client est honnête — on préfère refuser un coup qu'ouvrir une fenêtre
		-- de triche d'une seconde.
		MaxRewind = 0.25,
		-- Tolérance sur l'écart entre `clientTime` reçu et l'heure serveur.
		ClockTolerance = 0.12,
		-- Fréquence d'échantillonnage de l'historique de positions.
		PositionSampleRate = 20,
		-- Vitesse horizontale au-delà de laquelle AntiCheatService s'intéresse
		-- au joueur (sprint = 24, dash = 14 studs en 0.20 s = 70 en pointe).
		SpeedFlagThreshold = 80,
	},
}

export type Balance = typeof(Balance)

return TableUtil.deepFreeze(Balance)
