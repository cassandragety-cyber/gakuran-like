--!strict
--[[
	Result<T> — type de retour de toute validation serveur.

	Pourquoi ne pas retourner `nil` en cas d'échec : « refusé pour cause de
	cooldown » et « erreur interne » demandent des réactions opposées (l'un est
	normal, l'autre doit alerter). Un booléen ou un nil les confond ; un code
	d'erreur explicite les sépare et alimente directement AntiCheatService.
]]

export type Ok<T> = { ok: true, value: T }
export type Err = { ok: false, code: string, detail: string? }
export type Result<T> = Ok<T> | Err

--[[
	Résultat dont la valeur de succès ne porte aucune information : seule compte
	la distinction succès/refus. On ne l'écrit pas `Result<true>` — `Result.ok(true)`
	produit un `Ok<boolean>`, le littéral étant élargi, et les deux types ne se
	convertissent pas l'un dans l'autre.
]]
export type Verdict = Result<boolean>

local Result = {}

function Result.ok<T>(value: T): Result<T>
	local result: Ok<T> = { ok = true, value = value }
	return result
end

function Result.err<T>(code: string, detail: string?): Result<T>
	local result: Err = { ok = false, code = code, detail = detail }
	return result
end

--[[
	Déballe un Result en valeur brute, ou lève. À n'utiliser que là où l'échec
	est un bug de programmation (config invalide au boot), jamais sur une
	entrée réseau.
]]
function Result.expect<T>(result: Result<T>, context: string): T
	if result.ok then
		return result.value
	end
	error(`{context} : {result.code}{if result.detail then ` — {result.detail}` else ""}`, 2)
end

return Result
