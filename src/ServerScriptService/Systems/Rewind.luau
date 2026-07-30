--!strict
--[[
	Rembobinage de l'historique de positions (ADR-001).

	Module pur : il reçoit un tampon d'échantillons et un instant, il rend la pose
	interpolée. Aucune API Roblox, donc testable en fabriquant un historique.

	Pourquoi interpoler plutôt que prendre l'échantillon le plus proche :
	l'historique est échantillonné à 20 Hz, soit 50 ms entre deux poses. Un joueur
	qui sprinte à 24 studs/s parcourt 1,2 stud dans cet intervalle — prendre le
	voisin le plus proche introduirait jusqu'à 0,6 stud d'erreur arbitraire sur une
	portée de 7, uniquement à cause de la phase d'échantillonnage. C'est
	exactement le genre d'incohérence qui se ressent comme un « hit fantôme ».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Result = require(ReplicatedStorage.Shared.Result)
local RingBuffer = require(ReplicatedStorage.Shared.RingBuffer)

type Snapshot = CombatTypes.Snapshot
type History = RingBuffer.RingBuffer<Snapshot>

local Rewind = {}

local function interpolate(before: Snapshot, after: Snapshot, t: number): Snapshot
	local span = after.t - before.t
	local alpha = if span > 0 then math.clamp((t - before.t) / span, 0, 1) else 0

	-- Le vecteur de vue est interpolé linéairement puis renormalisé. Une
	-- interpolation sphérique serait plus juste mais, sur 50 ms de rotation
	-- humaine, l'écart est inférieur à la tolérance d'angle : on paierait un
	-- calcul trigonométrique par cible touchée pour rien.
	local look = before.look:Lerp(after.look, alpha)
	if look.Magnitude < 1e-4 then
		look = after.look
	end

	return {
		t = t,
		position = before.position:Lerp(after.position, alpha),
		look = look.Unit,
	}
end

--[[
	Pose d'un combattant à l'instant `t`.

	Retourne un `Result` plutôt qu'un nil : « je ne peux pas rembobiner si loin »
	et « je n'ai aucun historique » demandent des réactions différentes, et le code
	de refus remonte jusqu'au client pour expliquer le rejet.
]]
function Rewind.sampleAt(
	history: History,
	t: number,
	now: number,
	maxRewind: number
): Result.Result<Snapshot>
	if history.count == 0 then
		return Result.err("NoHistory", "aucun échantillon de position")
	end

	if now - t > maxRewind then
		return Result.err(
			"RewindExceeded",
			`rembobinage de {string.format("%.3f", now - t)} s demandé, borne à {maxRewind} s`
		)
	end

	local newest = RingBuffer.at(history, history.count) :: Snapshot
	-- Un instant postérieur au dernier échantillon n'est pas une triche : le
	-- client peut légitimement avoir agi entre deux échantillonnages serveur.
	-- On ne l'extrapole pas pour autant, faute de quoi un client en avance
	-- gagnerait de la portée gratuite.
	if t >= newest.t then
		return Result.ok(newest)
	end

	local oldest = RingBuffer.at(history, 1) :: Snapshot
	if t <= oldest.t then
		return Result.ok(oldest)
	end

	-- Parcours du plus récent vers le plus ancien : les coups portent presque
	-- toujours sur les derniers échantillons, la boucle sort en une ou deux
	-- itérations.
	for index = history.count, 2, -1 do
		local after = RingBuffer.at(history, index) :: Snapshot
		local before = RingBuffer.at(history, index - 1) :: Snapshot
		if t >= before.t and t <= after.t then
			return Result.ok(interpolate(before, after, t))
		end
	end

	return Result.err("NoBracket", "aucun couple d'échantillons n'encadre cet instant")
end

return Rewind
