--!strict
--[[
	L'état de combat autoritatif. Personne d'autre n'écrit ces valeurs.

	Le registre est indexé par **Model** et non par Player : un mannequin
	d'entraînement n'est pas un joueur, et il devra pourtant garder, encaisser et
	parer comme un joueur pour que les tranches 1.3 et 1.4 soient testables. Deux
	registres auraient signifié deux chemins de dégâts, donc deux endroits où la
	règle peut diverger. Un index secondaire par joueur garde l'accès direct.

	Le pas de temps vit dans `Stepper` : expiration des échéances, endurance,
	échantillonnage des positions, réplication. Un unique `Heartbeat`, aucun
	`task.delay` par combattant — un minuteur ne s'annule pas proprement quand un
	combattant est interrompu ou disparaît.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterService = require(script.Parent.CharacterService)
local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Net = require(ReplicatedStorage.Net)
local RingBuffer = require(ReplicatedStorage.Shared.RingBuffer)
local SessionService = require(script.Parent.SessionService)
local StaminaModel = require(ReplicatedStorage.Shared.Combat.StaminaModel)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)
local Stepper = require(script.Stepper)
local Transitions = require(script.Transitions)
local TuningService = require(script.Parent.TuningService)
local Types = require(script.Types)

-- 32 échantillons à 20 Hz valent 1,6 s, largement plus que le rembobinage
-- maximal de 0,25 s. La marge absorbe un pic de latence sans jamais rendre le
-- rembobinage plus permissif : c'est `Balance.Network.MaxRewind` qui le borne.
local HISTORY_SIZE = 32

export type Swing = Types.Swing
export type Combatant = Types.Combatant

local StateService = {}

StateService.Dependencies = { "SessionService", "CharacterService", "TuningService" }

--[[
	Réexports : les transitions vivent dans leur propre module, mais tout le code
	de combat s'adresse au service. On évite ainsi que chaque appelant connaisse le
	découpage interne.
]]
StateService.contextFor = Transitions.contextFor
StateService.requestTransition = Transitions.requestTransition
StateService.impose = Transitions.impose
StateService.markImpact = Transitions.markImpact

local records: { [Model]: Combatant } = {}
local byPlayer: { [Player]: Combatant } = {}

function StateService.get(model: Model): Combatant?
	return records[model]
end

function StateService.ofPlayer(player: Player): Combatant?
	return byPlayer[player]
end

function StateService.all(): { [Model]: Combatant }
	return records
end

function StateService.touch(combatant: Combatant)
	combatant.dirty = true
end

function StateService.tagCombat(combatant: Combatant)
	combatant.stamina.lastCombatAt = Clock.now()
end

--[[
	Retire des points de vie et retourne le total restant. Seul endroit du projet
	qui écrit `health` : un deuxième chemin de dégâts serait un deuxième endroit
	où oublier le passage à `Downed`.
]]
function StateService.applyDamage(combatant: Combatant, amount: number): number
	combatant.health = math.max(combatant.health - amount, 0)

	local humanoid = combatant.humanoid
	if humanoid then
		humanoid.Health = combatant.health
	end

	if combatant.health <= 0 then
		StateService.impose(combatant, "Downed")
	end
	StateService.touch(combatant)
	return combatant.health
end

function StateService.recordVerdict(combatant: Combatant, verdict: string, damage: number)
	combatant.lastVerdict = verdict
	combatant.lastDamage = damage
end

--[[
	Remet un combattant à neuf : pleine vie, garde intacte, état neutre.

	Utilisé par les mannequins d'entraînement, qui doivent redevenir frappables
	sans relancer la partie. `impose` refuserait de sortir de `Downed` (priorité
	inférieure), donc on réécrit l'état directement — c'est le seul endroit
	autorisé à le faire, et il est explicitement hors du jeu.
]]
function StateService.reset(combatant: Combatant)
	local balance = TuningService.balance()
	combatant.health = combatant.maxHealth
	combatant.guard = balance.Block.GuardHealth
	combatant.stamina.current = balance.Stamina.Max
	combatant.state = StateMachine.idle(Clock.now())
	combatant.lastSwing = nil
	combatant.swingHits = {}
	combatant.lastVerdict = nil
	combatant.lastDamage = 0

	local humanoid = combatant.humanoid
	if humanoid then
		humanoid.Health = combatant.health
	end
	StateService.touch(combatant)
end

function StateService.setSprinting(combatant: Combatant, active: boolean): boolean
	if active and not StaminaModel.canSprint(combatant.stamina, TuningService.balance()) then
		return false
	end
	combatant.sprinting = active
	return true
end

--[[
	Inscrit un combattant. `player` est nil pour un mannequin ; tout le reste du
	code de combat ne fait pas la différence, et c'est le but.
]]
function StateService.register(
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	player: Player?
): Combatant
	local balance = TuningService.balance()
	local now = Clock.now()

	local combatant: Combatant = {
		model = model,
		root = root,
		humanoid = humanoid,
		player = player,
		state = StateMachine.idle(now),
		health = balance.Character.MaxHealth,
		maxHealth = balance.Character.MaxHealth,
		stamina = { current = balance.Stamina.Max, lastCombatAt = 0 },
		guard = balance.Block.GuardHealth,
		dashReadyAt = 0,
		parryReadyAt = 0,
		sprinting = false,
		lastSwing = nil,
		swingHits = {},
		lastVerdict = nil,
		lastDamage = 0,
		history = RingBuffer.new(HISTORY_SIZE),
		lastSampleAt = 0,
		lastSyncAt = 0,
		dirty = true,
	}

	records[model] = combatant
	if player then
		byPlayer[player] = combatant
	end
	return combatant
end

function StateService.unregister(model: Model)
	local combatant = records[model]
	if combatant == nil then
		return
	end
	records[model] = nil
	if combatant.player then
		byPlayer[combatant.player] = nil
	end
end

local function replicate(combatant: Combatant, now: number)
	combatant.lastSyncAt = now
	combatant.dirty = false

	local player = combatant.player
	if player == nil then
		-- Un mannequin n'a personne à informer. Son affichage est piloté par
		-- TrainingService, qui possède son panneau.
		return
	end

	-- Tranche 1.2 : le propriétaire seulement. Les joueurs proches en auront
	-- besoin dès qu'il y aura un retour visuel à jouer sur autrui (tranche 1.3).
	Net.Server.fire(Definitions.CombatStateSync, player, {
		userId = player.UserId,
		state = combatant.state,
		health = combatant.health,
		stamina = combatant.stamina.current,
		guard = combatant.guard,
		dashReadyAt = combatant.dashReadyAt,
		parryReadyAt = combatant.parryReadyAt,
	})
end

function StateService.Init()
	CharacterService.onAdded(function(record)
		StateService.register(record.character, record.root, record.humanoid, record.player)
	end)

	-- L'état de combat disparaît avec le personnage : un état conservé entre deux
	-- vies ferait réapparaître un joueur étourdi ou au sol.
	CharacterService.onRemoving(function(player)
		local combatant = byPlayer[player]
		if combatant then
			StateService.unregister(combatant.model)
		end
	end)

	SessionService.onEnded(function(player)
		local combatant = byPlayer[player]
		if combatant then
			StateService.unregister(combatant.model)
		end
	end)
end

function StateService.Start()
	RunService.Heartbeat:Connect(function(deltaTime: number)
		Stepper.step(deltaTime, records, TuningService.balance(), replicate)
	end)
end

return StateService
