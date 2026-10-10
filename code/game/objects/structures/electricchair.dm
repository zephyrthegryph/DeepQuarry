/obj/structure/bed/chair/e_chair
	name = "electric chair"
	desc = "Looks absolutely SHOCKING!"
	icon_state = "echair0"
	var/on = 0
	var/obj/item/assembly/shock_kit/part = null
	COOLDOWN_DECLARE(shock_cooldown)

/obj/structure/bed/chair/e_chair/Initialize(mapload)
	. = ..()
	return

/// The ledger slot its kit sits in: a chair's only other slot is its buckle seat, which takes mobs, so `part` names this one.
#define SLOT_ECHAIR_KIT "echair_kit"

CAPABILITIES(/obj/structure/bed/chair/e_chair)
	slot(SLOT_ECHAIR_KIT, accepts = /obj/item/assembly/shock_kit, capacity = 1)
	without("dismantle")
	op("unwire", tool(TOOL_WRENCH), wait(0), label("Unwire"), then(PROC_REF(back_to_chair)))
	op("e_chair_toggle_effect", menu(), label("Toggle Electric Chair"), then(PROC_REF(e_chair_toggle_effect)))

/// A wrench takes the kit out and leaves a plain chair.
/obj/structure/bed/chair/e_chair/proc/back_to_chair(datum/act/op/A)
	var/obj/structure/bed/chair/C = new /obj/structure/bed/chair(loc)
	playsound(src, A.held.usesound, 50, 1)
	C.set_dir(dir)
	if(part)
		part.forceMove(loc)
		rel_clear(part, nameof(part.master))
		rel_take(src, nameof(part))
	replace_with(src, C)
	return OP_OK

/obj/structure/bed/chair/e_chair/proc/e_chair_toggle_effect(datum/act/op/A)
	var/mob/user = A.actor

	if(on)
		on = 0
		icon_state = "echair0"
	else
		on = 1
		icon_state = "echair1"
	to_chat(user, span_notice("You switch [on ? "on" : "off"] [src]."))
	return

/obj/structure/bed/chair/e_chair/set_dir()
	. = ..()
	if(.)
		cut_overlays()
		add_overlay(image('icons/obj/objects.dmi', src, "echair_over", MOB_LAYER + 1, dir))	//there's probably a better way of handling this, but eh. -Pete

/obj/structure/bed/chair/e_chair/proc/shock()
	if(!on)
		return
	if(!COOLDOWN_FINISHED(src, shock_cooldown))
		return
	COOLDOWN_START(src, shock_cooldown, 5 SECONDS)

	// special power handling
	var/area/A = get_area(src)
	if(!isarea(A))
		return
	if(!A.powered(EQUIP))
		return
	A.use_power_oneoff(5000, EQUIP)

	flick("echair1", src)
	fx_sparks(src, 12)
	if(has_buckled_mobs())
		for(var/mob/living/L as anything in src?.buckled_mob_list())
			L.burn_skin(85)
			to_chat(L, span_danger("You feel a deep shock course through your body!"))
			L.burn_skin(85)
			L.status_at_least(STAT_STUNNED, 600)
	visible_message(span_danger("The electric chair went off!"), span_danger("You hear a deep sharp shock!"))

	return

/// Old object verbs.

/obj/structure/bed/chair/e_chair/ownership()
	. = ..()
	. += owns(nameof(part), policy = OWN_CONTAINED)

/obj/structure/bed/chair/e_chair/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image('icons/obj/objects.dmi', "echair_over", layer = MOB_LAYER + 1, dir = dir))
