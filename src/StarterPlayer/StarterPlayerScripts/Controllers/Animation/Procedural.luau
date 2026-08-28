--!strict
--[[
	Lecture d'une pose procédurale sur les Motor6D du personnage.

	Pourquoi ça existe : ADR-009 pose qu'on développe sans assets d'animation, et
	qu'un `id = 0` doit produire **quelque chose de lisible** plutôt que rien. Un
	combat sans retour visuel ne se teste pas — on ne sait ni si on a paré, ni ce
	qu'on a encaissé.

	Deux détails techniques portent tout le module.

	Le premier est l'ORDRE D'EXÉCUTION. L'`Animator` de Roblox réécrit
	`Motor6D.Transform` à chaque frame pendant l'étape « Character ». Écrire avant
	elle ne produit rien de visible. On s'accroche donc juste après, via
	`BindToRenderStep` à `RenderPriority.Character.Value + 1` : nos poses se
	superposent alors à la locomotion au lieu de lutter contre elle.

	Le second est que `Transform` est un offset RELATIF au repos de la jointure.
	On interpole donc depuis l'identité, ce qui rend les poses additives : la
	marche continue de jouer sous une garde levée, exactement comme le ferait une
	vraie animation sur un `AnimationTrack` de priorité supérieure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Clock)
local Log = require(ReplicatedStorage.Shared.Log)
local PosesConfig = require(ReplicatedStorage.Config.Poses)
local Probe = require(script.Parent.Probe)
local Rig = require(script.Parent.Rig)

local SCOPE = "Procedural"

-- Juste après l'étape qui applique les animations : c'est la seule position où
-- une écriture sur `Transform` survit à la frame.
local BIND_PRIORITY = Enum.RenderPriority.Character.Value + 1
local BIND_NAME = "BanchouProceduralPose"

type Pose = PosesConfig.Pose

type Playing = {
	pose: Pose,
	startedAt: number,
	duration: number,
	-- Une pose tenue ne se termine pas d'elle-même : seul `stop` la relâche.
	looped: boolean,
	-- Instant du relâchement demandé, pour redescendre proprement au lieu de
	-- disparaître d'un coup.
	releasedAt: number?,
}

local Procedural = {}

local playing: { [string]: Playing } = {}
local bound = false

--[[
	Lie le personnage. Le recensement des jointures, sa mise à jour pendant
	l'assemblage et son diagnostic appartiennent à `Rig` : ici on ne remet à zéro
	que ce qui est en cours de lecture.
]]
function Procedural.bindCharacter(character: Model)
	table.clear(playing)
	Rig.bindCharacter(character)
end

--[[
	État du moteur de pose, pour le panneau F2. Le drapeau `bound` complète le
	diagnostic de `Rig` : il distingue « le rig n'a pas de jointure » de « la boucle
	de rendu n'a jamais démarré », deux pannes qui donnent le même personnage
	immobile.
]]
function Procedural.diagnose(): (string, number, number, boolean)
	local rigLabel, resolved, required = Rig.diagnose()
	return rigLabel, resolved, required, bound
end

--[[
	Démarre une capture journalisée au point d'écriture. Une ligne par frame :
	combien de jointures ont été écrites, laquelle sert de témoin, l'angle écrit,
	et ce qu'il en restait à la frame suivante.
]]
function Procedural.capture(seconds: number)
	Probe.capture(seconds)
end

function Procedural.writeStatus(): (number, string, boolean)
	return Probe.status()
end

function Procedural.hasPose(key: string): boolean
	return PosesConfig.Poses[key] ~= nil
end

--[[
	Démarre une pose. `duration` vient de `Animations[clé].targetDuration`, donc
	de la même source que le frame data : la pose dure exactement ce que dure le
	coup, et l'impact visuel ne peut pas dériver de l'impact réel.
]]
function Procedural.play(key: string, duration: number, looped: boolean): boolean
	local pose = PosesConfig.Poses[key]
	if pose == nil then
		return false
	end
	if duration <= 0 then
		Log.warn(SCOPE, `durée nulle pour la pose {key}, lecture ignorée`)
		return false
	end

	--[[
		Une pose TENUE déjà en cours n'est pas relancée : elle est maintenue.

		La distinction compte dès qu'une intention se ré-affirme — la garde est
		redemandée toutes les demi-secondes tant que la touche est enfoncée et que
		l'autorité n'a pas suivi. Redémarrer relancerait la montée à chaque essai,
		et la garde pulserait à l'écran. Une pose non tenue, elle, doit bien
		repartir : deux coups identiques d'affilée sont deux coups.
	]]
	local existing = playing[key]
	if looped and existing ~= nil and existing.releasedAt == nil then
		return true
	end

	playing[key] = {
		pose = pose,
		startedAt = Clock.monotonic(),
		duration = duration,
		looped = looped,
		releasedAt = nil,
	}
	return true
end

--[[
	Relâche une pose tenue. Elle redescend sur la durée de son `attack` plutôt que
	de retomber d'un coup — une garde qui disparaît instantanément se lit comme un
	bug d'affichage.
]]
function Procedural.stop(key: string)
	local entry = playing[key]
	if entry == nil or entry.releasedAt ~= nil then
		return
	end
	entry.releasedAt = Clock.monotonic()
end

function Procedural.isPlaying(key: string): boolean
	return playing[key] ~= nil
end

function Procedural.activeCount(): number
	local count = 0
	for _ in playing do
		count += 1
	end
	return count
end

--[[
	Poids de la pose à cet instant : 0 au repos, 1 en pose pleine.

	Retourne nil quand la lecture est terminée, ce qui est le signal de retrait.
	Séparer « quel poids » de « faut-il continuer » ferait calculer deux fois la
	même enveloppe.
]]
local function weightAt(entry: Playing, now: number): number?
	local pose = entry.pose
	local elapsed = now - entry.startedAt
	local attackTime = math.max(pose.attack * entry.duration, 1e-3)

	local released = entry.releasedAt
	if released ~= nil then
		-- Descente depuis le poids atteint, sur la même durée que la montée.
		local heldWeight = math.clamp((released - entry.startedAt) / attackTime, 0, 1)
		local fade = (now - released) / attackTime
		if fade >= 1 then
			return nil
		end
		return heldWeight * (1 - fade)
	end

	if elapsed < attackTime then
		return elapsed / attackTime
	end

	if entry.looped then
		return 1
	end

	local releaseTime = pose.release * entry.duration
	local holdUntil = entry.duration - releaseTime
	if elapsed < holdUntil then
		return 1
	end
	if releaseTime <= 0 or elapsed >= entry.duration then
		return nil
	end
	return 1 - (elapsed - holdUntil) / releaseTime
end

--[[
	Compose toutes les poses actives sur les jointures.

	Le mélange est une **moyenne pondérée**, pas une accumulation, et la
	distinction n'est pas cosmétique : `BlockStart` et `BlockHold` visent les
	mêmes jointures avec la même cible, et les additionner produirait une double
	rotation — bras traversant la tête pendant le recouvrement des deux lectures.
	La moyenne rend ce recouvrement invisible, ce qui est le comportement attendu
	d'une pose qui prend le relais d'une autre.

	L'intensité totale reste bornée à 1 après la moyenne, si bien qu'une réaction
	à un coup encaissé se mélange à la garde au lieu de l'écraser : le défenseur
	encaisse sans jamais paraître baisser les bras.
]]
local function update()
	Probe.beginFrame()
	-- Relecture AVANT toute écriture : c'est ce décalage d'une frame qui rend un
	-- écrasement détectable. Relire juste après avoir écrit ne prouverait rien,
	-- puisque personne n'a encore eu l'occasion d'écraser.
	Probe.readBack(Rig.joints())

	if next(playing) == nil then
		Probe.endFrame()
		return
	end

	local now = Clock.monotonic()
	local blended: { [string]: CFrame } = {}
	local weights: { [string]: number } = {}

	for key, entry in playing do
		local weight = weightAt(entry, now)
		if weight == nil then
			playing[key] = nil
			continue
		end
		if weight <= 0 then
			continue
		end

		for jointName, target in entry.pose.joints do
			-- Lerp incrémental à `poids / poids cumulé` : c'est la forme
			-- récurrente de la moyenne pondérée, sans stocker la liste des cibles.
			local accumulated = (weights[jointName] or 0) + weight
			local current = blended[jointName] or CFrame.identity
			blended[jointName] = current:Lerp(target, weight / accumulated)
			weights[jointName] = accumulated
		end
	end

	for jointName, motor in Rig.joints() do
		local average = blended[jointName]
		if average then
			local value = CFrame.identity:Lerp(average, math.min(weights[jointName], 1))
			motor.Transform = value
			Probe.wrote(jointName, Rig.classOf(jointName), value)
		end
	end

	Probe.endFrame()
end

function Procedural.Start()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep(BIND_NAME, BIND_PRIORITY, update)
end

function Procedural.Stop()
	if not bound then
		return
	end
	bound = false
	RunService:UnbindFromRenderStep(BIND_NAME)
end

return Procedural
