--!strict
--[[
	Rate limiter « token bucket », pur : aucune dépendance à l'API Roblox, le
	temps est injecté par l'appelant. Testable exhaustivement hors moteur.

	Pourquoi un bucket plutôt qu'un simple « 1 appel toutes les N secondes » :
	le combat produit légitimement des rafales (un chain M1 de 4 coups en 1,5 s)
	suivies de silence. Une cadence fixe punirait le jeu normal ; un bucket
	autorise la rafale tant que la moyenne tient.
]]

export type Bucket = {
	capacity: number,
	refillPerSecond: number,
	tokens: number,
	lastRefill: number,
}

local TokenBucket = {}

function TokenBucket.new(capacity: number, refillPerSecond: number, now: number): Bucket
	return {
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		tokens = capacity,
		lastRefill = now,
	}
end

--[[
	Tente de consommer `amount` jetons. Retourne false sans rien consommer si le
	solde est insuffisant — un refus ne doit jamais pénaliser le solde, sinon un
	joueur bloqué le reste indéfiniment.
]]
function TokenBucket.tryConsume(bucket: Bucket, now: number, amount: number): boolean
	local elapsed = now - bucket.lastRefill
	if elapsed > 0 then
		bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)
		bucket.lastRefill = now
	end

	if bucket.tokens < amount then
		return false
	end

	bucket.tokens -= amount
	return true
end

return TokenBucket
