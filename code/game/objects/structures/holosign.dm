/obj/structure/holosign
	name = "holo sign"
	icon = 'icons/effects/effects.dmi'
	anchored = TRUE
	var/obj/item/holosign_creator/projector
	max_integrity = 10
	explosion_resistance = 1

/*	if(overlays) // Fucking god damnit why do we have to have an entire different subsystem for this shit from other codebases.
		overlays.add_overlay(src, icon, icon_state, ABOVE_MOB_LAYER, plane, dir, alpha, RESET_ALPHA) //you see mobs under it, but you hit them like they are above it
		alpha = 0
*/

CAPABILITIES(/obj/structure/holosign)
	links(/obj/structure/holosign::projector, /obj/item/holosign_creator::signs, b_many = TRUE)
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	param(nameof(projector), pos = 1)

/obj/structure/holosign/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(user.get_attack_speed())
	user.do_attack_animation(src)
	play_sfx(loc, SFX_WEAPONS_EGLOVES, 1.6, extrarange = 0)
	take_damage(5, BRUTE, MELEE, sound_effect = FALSE)
	return TRUE

/obj/structure/holosign/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src)
	play_sfx(loc, SFX_WEAPONS_EGLOVES, 1.6, extrarange = 0)
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
	EXPIRY_DECLARE(buzzed)
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

CAPABILITIES(/obj/structure/holosign/barrier/medical)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

/// Something walked into it (the bump action's notice).
/obj/structure/holosign/barrier/medical/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	if(ishuman(AM) && !CheckHuman(AM))
		if(COOLDOWN_FINISHED(src, buzzed))
			play_sfx(get_turf(src), SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
			EXPIRY_SET(src, buzzed, 6 SECONDS, CLOCK_WORLD)

		icon_state = "holo_medical-deny"
		after(src, 10 SECONDS, PROC_REF(reset_deny_icon), key = "medical_holosign_deny_reset")

/obj/structure/holosign/barrier/medical/proc/reset_deny_icon()
	icon_state = "holo_medical"

/obj/structure/holosign/barrier/medical/proc/CheckHuman(mob/living/carbon/human/H)
	if(H.get_species() == SPECIES_XENOCHIMERA)
		return FALSE
	var/threat = H.contagion_threat()
	if(get_disease_danger_value(threat) > get_disease_danger_value(DISEASE_MINOR))
		return FALSE
	return TRUE
