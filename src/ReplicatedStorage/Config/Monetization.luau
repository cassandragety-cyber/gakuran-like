--!strict
--[[
	Gamepasses et dev products.

	Tous les `id` valent 0 tant que les produits n'existent pas sur la page du
	jeu. MonetizationService (Phase 7) ignore silencieusement une entrée à 0
	côté serveur et l'UI ne l'affiche pas : le jeu tourne donc normalement avant
	que la monétisation ne soit créée, et l'activer consiste à remplir un nombre
	ici.

	COMMENT CRÉER CES PRODUITS
	Chaque entrée porte, dans son commentaire, le nom exact à saisir, le prix
	suggéré en Robux et ce que le produit débloque. Sur la page du jeu :
	Creator Hub -> votre expérience -> Monetization -> Passes / Developer
	Products -> Create. Une fois créé, copiez l'ID et remplacez le 0.

	RÈGLE PRODUIT NON NÉGOCIABLE (brief §5.7) : aucun produit ne vend de statistique
	de combat. `grantsCombatAdvantage` doit rester false partout ; Config.validate()
	fait échouer le boot si un jour quelqu'un le passe à true.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

export type Gamepass = {
	id: number,
	name: string,
	suggestedPrice: number,
	grantsCombatAdvantage: boolean,
}

export type DevProduct = {
	id: number,
	name: string,
	suggestedPrice: number,
	grantsCombatAdvantage: boolean,
}

local Monetization = {
	Gamepasses = {
		--[[
			À créer sous le nom « Banchou VIP ».
			Prix suggéré : 399 R$.
			Débloque : point de spawn VIP (toit du lycée), tag de chat doré,
			et un 2e slot de style (le joueur conserve deux styles et bascule
			de l'un à l'autre hors combat). Aucun bonus de statistique.
		]]
		VIP = {
			id = 0,
			name = "Banchou VIP",
			suggestedPrice = 399,
			grantsCombatAdvantage = false,
		} :: Gamepass,

		--[[
			À créer sous le nom « Reroll Illimité 24h ».
			Prix suggéré : 199 R$.
			Débloque : rerolls de style illimités pendant 24 h à partir de
			l'achat (l'expiration est stockée dans le profil, pas côté client).
			Ne modifie pas les taux de rareté — c'est du temps gagné, pas de la
			chance achetée.
		]]
		UnlimitedReroll24h = {
			id = 0,
			name = "Reroll Illimité 24h",
			suggestedPrice = 199,
			grantsCombatAdvantage = false,
		} :: Gamepass,
	},

	DevProducts = {
		--[[
			« 1 Reroll de style ». Prix suggéré : 49 R$.
			Un reroll unique, en plus de ceux payables en Yen.
		]]
		RerollSingle = {
			id = 0,
			name = "1 Reroll de style",
			suggestedPrice = 49,
			grantsCombatAdvantage = false,
		} :: DevProduct,

		--[[
			« 10 Rerolls de style ». Prix suggéré : 399 R$.
			Lot de 10 rerolls, crédités sur le profil.
		]]
		RerollPack10 = {
			id = 0,
			name = "10 Rerolls de style",
			suggestedPrice = 399,
			grantsCombatAdvantage = false,
		} :: DevProduct,

		--[[
			« 10 000 Yen ». Prix suggéré : 99 R$.
			Monnaie douce, dépensable en cosmétiques et en rerolls.
		]]
		YenSmall = {
			id = 0,
			name = "10 000 Yen",
			suggestedPrice = 99,
			grantsCombatAdvantage = false,
		} :: DevProduct,

		--[[
			« 60 000 Yen ». Prix suggéré : 499 R$.
			Même monnaie, meilleur ratio.
		]]
		YenLarge = {
			id = 0,
			name = "60 000 Yen",
			suggestedPrice = 499,
			grantsCombatAdvantage = false,
		} :: DevProduct,
	},
}

return TableUtil.deepFreeze(Monetization)
