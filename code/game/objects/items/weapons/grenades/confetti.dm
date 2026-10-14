/obj/item/grenade/confetti
	desc = "It is set to detonate in 2 seconds. These party grenades will make everyone jump with joy (or fright)!"
	name = "grenatti"
	icon = 'icons/obj/grenade.dmi'
	icon_state = "grenade"
	det_time = 20
	item_state = "grenade"
	var/datum/effect/effect/system/confetti_spread
	var/confetti_strength = 8

/obj/item/grenade/confetti/Initialize(mapload)
	. = ..()
	confetti_spread.attach(src)

CAPABILITIES(/obj/item/grenade/confetti)
	configure(item_worn(slots = SLOT_BELT))
	owns_one(nameof(confetti_spread), /datum/effect/effect/system/confetti_spread, starts = /datum/effect/effect/system/confetti_spread)

/obj/item/grenade/confetti/detonate() //Find a good confetti firework or pop sound effect later
	start_effect_sprayer(confetti_spread, confetti_strength, 'sound/effects/snap.ogg')

/obj/item/grenade/confetti/party_ball //Intended to be used only with the confetti cannon.
	name = "party ball"
	desc = "Full of !!FUN!!"
	icon = 'icons/obj/grenade.dmi'
	icon_state = "party_ball"
	confetti_strength = 2
	det_time = 1

CAPABILITIES(/obj/item/grenade/confetti/party_ball)
	configure(item_thrown(force = 0))

/obj/item/grenade/confetti/party_ball/detonate() //Could condense this by making the sound a variable in the parent but I'm lazy.
	start_effect_sprayer(confetti_spread, confetti_strength, 'sound/effects/confetti_ball.ogg')
