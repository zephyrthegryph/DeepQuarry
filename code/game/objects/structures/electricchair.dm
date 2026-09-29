/obj/structure/bed/chair/e_chair
	name = "electric chair"
	desc = "Looks absolutely SHOCKING!"
	icon_state = "echair0"
	var/on = 0
	var/obj/item/assembly/shock_kit/part = null
	COOLDOWN_DECLARE(shock_cooldown)

/obj/structure/bed/chair/e_chair/Initialize(mapload)
	. = ..()
	add_overlay(image('icons/obj/objects.dmi', src, "echair_over", MOB_LAYER + 1, dir))
	return

/obj/structure/bed/chair/e_chair/wrench_act(mob/user, obj/item/W)
	var/obj/structure/bed/chair/C = new /obj/structure/bed/chair(loc)
	playsound(src, W.usesound, 50, 1)
	C.set_dir(dir)
	if(part)
		part.forceMove(loc)
		rel_clear(part, nameof(part.master))
		own_take(src, nameof(part))
	replace_with(src, C)
	return TRUE

/obj/structure/bed/chair/e_chair/proc/e_chair_toggle_effect(mob/user, obj/item/held, datum/interaction/interaction)

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
	COOLDOWN_START(src, shock_cooldown, 50)

	// special power handling
	var/area/A = get_area(src)
	if(!isarea(A))
		return
	if(!A.powered(EQUIP))
		return
	A.use_power_oneoff(5000, EQUIP)
	var/light = A.power_light
	A.update_icon()

	flick("echair1", src)
	fx_sparks(src, 12)
	if(has_buckled_mobs())
		for(var/mob/living/L as anything in src?.buckled_mob_list())
			L.burn_skin(85)
			to_chat(L, span_danger("You feel a deep shock course through your body!"))
			L.burn_skin(85)
			L.status_at_least(EFFECT_STUNNED, 600)
	visible_message(span_danger("The electric chair went off!"), span_danger("You hear a deep sharp shock!"))

	A.power_light = light
	A.update_icon()
	return

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/structure/bed/chair/e_chair, \
	INTERACT_VERB("Toggle Electric Chair", PROC_REF(e_chair_toggle_effect)), \
)

/obj/structure/bed/chair/e_chair/declare_ownership(decl)
	..()
	own(decl, nameof(part), policy = OWN_CONTAINED)
