--!strict
--[[
	Outils de développement : liste blanche de réglage à chaud, accès
	administrateur, paramètres du panneau F2.

	`Tunables` est une LISTE BLANCHE, pas une liste noire : un chemin absent est
	refusé, même en Studio. ConfigValidator vérifie au boot que chaque chemin
	existe réellement dans `Balance` et que sa valeur courante tient dans les
	bornes — une entrée mal orthographiée fait échouer le démarrage plutôt que de
	produire un curseur inerte.

	Ce qui n'est délibérément PAS réglable à chaud : les durées d'animation. Les
	modifier casserait le contrat vérifié au boot entre `Animations` et `Balance`
	(ADR-009). Il faut passer par les fichiers et redémarrer, ce qui est
	l'intention.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

--[[
	`target` dit où la valeur atterrit :
	  - "Balance" : un chemin dans la table d'équilibrage vivante. La valeur
	    initiale est celle de `Config/Balance`, il n'y a donc pas de `default`.
	  - "Switch"  : un interrupteur de développement qui n'existe pas dans
	    l'équilibrage et porte donc sa propre valeur par défaut.

	Un seul type pour les deux évite d'avoir deux listes blanches, deux chemins de
	validation et deux façons de se tromper.
]]
export type TuningTarget = "Balance" | "Switch"

export type Tunable = {
	target: TuningTarget,
	min: number,
	max: number,
	-- Pas d'incrément du curseur. Les durées de combat vivent sur une grille de
	-- 0,05 s pour rester atteignables en frames entières à 60 fps.
	step: number,
	label: string,
	-- Renseigné uniquement pour les interrupteurs.
	default: number?,
	--[[
		Interrupteur dont l'effet est purement client (un affichage). Le serveur
		l'accepte, le stocke et le diffuse sans rien en faire lui-même. Sans cette
		distinction, il faudrait déclarer côté serveur un effet vide pour chaque
		option d'affichage, et un effet vide finit toujours par masquer un oubli.
	]]
	clientOnly: boolean?,
}

local function tunable(min: number, max: number, step: number, label: string): Tunable
	return { target = "Balance", min = min, max = max, step = step, label = label }
end

local function switch(
	min: number,
	max: number,
	step: number,
	label: string,
	default: number,
	clientOnly: boolean?
): Tunable
	return {
		target = "Switch",
		min = min,
		max = max,
		step = step,
		label = label,
		default = default,
		clientOnly = clientOnly,
	}
end

local Debug = {
	--[[
		UserId autorisés à ouvrir le panneau et à régler en production.

		Vide par défaut, et ce défaut compte : tant que cette liste est vide, les
		remotes de développement ne sont pas instanciés hors Studio et la table
		d'équilibrage vivante est regelée (ADR-013).
	]]
	AdminUserIds = {} :: { number },

	Panel = {
		Keybind = Enum.KeyCode.F2,
		-- Rafraîchissement de l'affichage. 10 Hz suffit à lire des échéances et
		-- évite de payer un recalcul d'interface à chaque frame de combat.
		RefreshRate = 10,
		Width = 380,
	},

	Tunables = {
		["Parry.Window"] = tunable(0.05, 0.60, 0.01, "Fenêtre de parade"),
		["Parry.AttackerStun"] = tunable(0.20, 3.00, 0.05, "Stun renvoyé à l'attaquant"),
		["Parry.Cooldown"] = tunable(0.00, 2.00, 0.05, "Cooldown de parade"),
		["Parry.StaminaReward"] = tunable(0, 50, 1, "Endurance rendue par la parade"),

		["Combat.ComboWindow"] = tunable(0.20, 1.20, 0.05, "Fenêtre de combo"),
		["Combat.WhiffResetDelay"] = tunable(
			0.20,
			2.00,
			0.05,
			"Reset de chaîne après un coup dans le vide"
		),

		["Block.DamageMultiplier"] = tunable(0.00, 1.00, 0.05, "Dégâts encaissés en garde"),
		["Block.GuardHealth"] = tunable(10, 200, 5, "Jauge de garde"),
		["Block.GuardBreakStun"] = tunable(0.40, 4.00, 0.10, "Stun de garde brisée"),

		["Dash.Distance"] = tunable(4, 40, 1, "Distance de dash"),
		["Dash.InvulnerabilityDuration"] = tunable(0.00, 0.50, 0.01, "I-frames de dash"),
		["Dash.Cooldown"] = tunable(0.30, 4.00, 0.10, "Cooldown de dash"),
		["Dash.StaminaCost"] = tunable(0, 60, 1, "Coût du dash"),

		["Stamina.RegenInCombat"] = tunable(0, 40, 1, "Régén. en combat"),
		["Stamina.RegenOutOfCombat"] = tunable(0, 60, 1, "Régén. hors combat"),
		["Stamina.SprintDrainPerSecond"] = tunable(0, 40, 1, "Coût du sprint"),
		["Stamina.MinimumToAct"] = tunable(0, 50, 1, "Seuil d'action"),

		["Character.SprintSpeed"] = tunable(16, 40, 1, "Vitesse de sprint"),
		["Hitbox.FacingDot"] = tunable(-1.0, 1.0, 0.05, "Cône de validation d'angle"),
		["Hitbox.ServerToleranceStuds"] = tunable(0, 10, 0.5, "Marge serveur de portée"),

		--[[
			Latence simulée aller-retour, en millisecondes, appliquée par le
			serveur. C'est ce qui permet de tenir le critère d'acceptation à
			150 ms sans deux machines distantes. Voir Net/LatencySim : la file
			préserve l'ordre des paquets, sinon on déboguerait des inversions
			qu'on aurait soi-même créées.
		]]
		["SimulatedLatencyMs"] = switch(0, 400, 10, "Latence simulée (ms aller-retour)", 0),

		-- Booléen exprimé en 0/1 : un seul type d'entrée réglable vaut mieux que
		-- deux listes blanches à tenir cohérentes.
		["ShowHitboxes"] = switch(0, 1, 1, "Afficher les hitbox", 0, true),
	} :: { [string]: Tunable },
}

return TableUtil.deepFreeze(Debug)
