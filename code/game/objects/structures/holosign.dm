/obj/structure/holosign
	name = "holo sign"
	icon = 'icons/effects/effects.dmi'
	anchored = TRUE
	var/obj/item/holosign_creator/projector
	max_integrity = 10
	explosion_resistance = 1

/obj/structure/holosign/Initialize(mapload, source_projector)
	. = ..()
	if(source_projector)
		projector = source_projector
		LAZYADD(projector.signs, src)
/*	if(overlays) // Fucking god damnit why do we have to have an entire different subsystem for this shit from other codebases.
		overlays.add_overlay(src, icon, icon_state, ABOVE_MOB_LAYER, plane, dir, alpha, RESET_ALPHA) //you see mobs under it, but you hit them like they are above it
		alpha = 0
*/

REF_BACKLIST(/obj/structure/holosign, list("projector" = "signs"))

/obj/structure/holosign/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/holosign_hand,
		/datum/interaction/entry_item/holosign_item,
	)
	..()

/// Old attack_hand: punch the sign.
/datum/interaction/entry_hand/holosign_hand
	id = "holosign_hand"
	name = "Use"
	effect = /obj/structure/holosign/proc/interaction_hand

/obj/structure/holosign/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed())
	user.do_attack_animation(src)
	playsound(loc, 'sound/weapons/egloves.ogg', 80, 1)
	take_damage(5, BRUTE, MELEE, sound_effect = FALSE)
	return TRUE

/// Old attackby: hit the sign with a weapon.
/datum/interaction/entry_item/holosign_item
	id = "holosign_item"
	name = "Use"
	effect = /obj/structure/holosign/proc/interaction_item

/obj/structure/holosign/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src)
	playsound(loc, 'sound/weapons/egloves.ogg', 80, 1)
	receive_weapon_hit(W, user)
	return TRUE

/obj/structure/holosign/wetsign
	name = "wet floor sign"
	desc = "The words flicker as if they mean nothing."
	icon_state = "holosign"

/obj/structure/holosign/barrier/combifan
	name = "holo combifan"
	desc = "A holographic barrier resembling a blue-accented tiny fan. Though it does not prevent solid objects from passing through, gas and temperature changes are kept out."
	icon_state = "holo_firelock"
	anchored = TRUE
	density = FALSE
	layer = ABOVE_TURF_LAYER
	can_atmos_pass = ATMOS_PASS_NO
	rad_insulation = RAD_LIGHT_INSULATION
	alpha = 150

/obj/structure/holosign/barrier/combifan/Initialize(mapload)
	.=..()
	update_nearby_tiles()

/obj/structure/holosign/barrier/medical
	name = "\improper Vey-Med holobarrier"
	desc = "A holobarrier that uses biometrics to detect viruses. Denies passing to personnel with easily-detected, malicious viruses. Good for quarantines."
	icon_state = "holo_medical"
	alpha = 125
	var/buzzed = 0
	rad_insulation = RAD_NO_INSULATION

/obj/structure/holosign/barrier/medical/CanPass(atom/movable/mover, border_dir)
	. = ..()
	if(mover.has_buckled_mobs())
		for(var/mob/living/L as anything in src?.buckled_mob_list())
			if(ishuman(L))
				if(CheckHuman(L))
					return FALSE
	if(ishuman(mover))
		return CheckHuman(mover)
	return TRUE

/obj/structure/holosign/barrier/medical/Bumped(atom/movable/AM)
	. = ..()
	if(ishuman(AM) && !CheckHuman(AM))
		if(COOLDOWN_FINISHED(src, buzzed))
			playsound(get_turf(src), 'sound/machines/buzz-sigh.ogg', 50, 1)
			buzzed = (world.time + 60)

		icon_state = "holo_medical-deny"
		om_after_replace(src, 10 SECONDS, PROC_REF(reset_deny_icon))

/obj/structure/holosign/barrier/medical/proc/reset_deny_icon()
	icon_state = "holo_medical"

/obj/structure/holosign/barrier/medical/proc/CheckHuman(mob/living/carbon/human/H)
	if(H.get_species() == SPECIES_XENOCHIMERA)
		return FALSE
	var/threat = H.contagion_threat()
	if(get_disease_danger_value(threat) > get_disease_danger_value(DISEASE_MINOR))
		return FALSE
	return TRUE
