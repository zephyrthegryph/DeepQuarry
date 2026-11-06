///////////
//MATCHES//
///////////
/obj/item/flame/match
	name = "match"
	desc = "A simple match stick, used for lighting fine smokables."
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "match_unlit"
	var/burnt = 0
	var/smoketime = 5
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/flame/match)
	configure(item_worn(slots = SLOT_EARS))
	configure(item_combat(attack_verbs = list("burnt", "singed")))
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/flame/match/flame_step(datum/act/timer/A)
	if(isliving(loc))
		var/mob/living/M = loc
		M.ignite_mob()
	var/turf/location = get_turf(src)
	smoketime--
	if(smoketime < 1)
		burn_out()
		return
	if(location)
		location.hotspot_expose(700, 5)
		return

/obj/item/flame/match/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()
	//If dropped, put ourselves out
	//not before lighting up the turf we land on, though.
	if(lit)
		after(src, 0, PROC_REF(burn_out_where_dropped))
	return ..()

/obj/item/flame/match/proc/light(mob/user)
	play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_MATCHSTICK_LIT)
	set_lit(1)
	set_injury_kind(INJURY_BURN)
	set_icon_state("match_lit")
	name = "burning match"
	desc = "A match. This one is presently on fire."

/obj/item/flame/match/proc/burn_out()
	set_lit(0)
	burnt = 1
	set_injury_kind(INJURY_BLUNT)
	set_icon_state("match_burnt")
	set_item_state("cigoff")
	name = "burnt match"
	desc = "A match. This one has seen better days."

/// Lights up the turf the match landed on, then goes out.
/obj/item/flame/match/proc/burn_out_where_dropped()
	var/turf/location = loc
	if(istype(location))
		location.hotspot_expose(700, 5)
	burn_out()
