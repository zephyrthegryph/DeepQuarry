/obj/structure/closet/statue
	name = "statue"
	desc = "An incredibly lifelike marble carving"
	icon = 'icons/obj/statue.dmi'
	icon_state = "human_male"
	density = TRUE
	anchored = TRUE
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE
	closet_appearance = null
	// The statue starts at the encased mob's remaining wellness (vitality * endurance) + 100
	// integrity (set in Initialize). Structural damage taken while petrified is transferred
	// back to the mob on release; meanwhile the stasis field cancels all injury to the mob.
	max_integrity = 100
	/// Integrity the statue started at; damage below this is dealt to the mob on release.
	var/original_int = 100
	var/timer = 240 //eventually the person will be freed

/obj/structure/closet/statue/Initialize(mapload, mob/living/L)
	. = ..()
	var/found_target = FALSE
	if(L && (ishuman(L) || L.isMonkey() || iscorgi(L)))
		found_target = TRUE
		if(L?.buckled_to())
			var/atom/movable/_tmp_buck_9 = L?.buckled_to()
			_tmp_buck_9.unbuckle_mob(L, TRUE)
			L.set_anchored(FALSE)
		L.forceMove(src)
		L.set_sdisabilities(L.sdisabilities | MUTE)
		max_integrity = L.get_endurance() + 100
		original_int = L.vitality() * L.get_endurance() + 100
		update_integrity(original_int) //stoning damaged mobs will result in easier to shatter statues
		om_hook(L, /datum/om/event/before/living_injure, src, PROC_REF(stasis_block_injury))
		if(ishuman(L))
			name = "statue of [L.name]"
			if(L.gender == "female")
				icon_state = "human_female"
		else if(L.isMonkey())
			name = "statue of a monkey"
			icon_state = "monkey"
		else if(iscorgi(L))
			name = "statue of a corgi"
			icon_state = "corgi"
			desc = "If it takes forever, I will wait for you..."

	if(!found_target) //meaning if the statue didn't find a valid target
		return INITIALIZE_HINT_QDEL

	after(src, timer * 2 SECONDS, PROC_REF(release)) // the old countdown: one per 2 s step

/// The petrification wears off (its timer): the statue frees whoever is inside.
/obj/structure/closet/statue/proc/release()
	if(QDELETED(src))
		return
	timer = 0
	dump_contents()
	consume(src)

/obj/structure/closet/statue/dump_contents()
	latent_materialize_all()

	for(var/obj/O in slot_contents())
		O.forceMove(get_turf(src))

	for(var/mob/living/M in slot_contents())
		M.forceMove(loc) // Might be in a belly
		M.set_sdisabilities(M.sdisabilities & (~MUTE))
		om_unhook(M, /datum/om/event/before/living_injure, src)
		if(get_integrity() < original_int) //any new damage the statue incurred is transfered to the mob
			M.injure(INJURY_BLUNT, original_int - get_integrity(), null, src)
		M.reset_perspective() // Fixes a blackscreen flicker

// the statue's mob is released unmuted and unregistered.
/obj/structure/closet/statue/on_destroy(force)
	// Release the mob properly (unmuted, unregistered) before the base
	// Destroy() spills the interior.
	dump_contents()
	..()

/// Go-go gadget stasis field: the encased mob can't be hurt while it's rock.
/obj/structure/closet/statue/proc/stasis_block_injury(mob/living/source, datum/om/event/before/living_injure/event)
	EVENT_HANDLER
	if(source.loc == src)
		return COMPONENT_CANCEL_INJURY

/obj/structure/closet/statue/open()
	return

/obj/structure/closet/statue/close()
	return

/obj/structure/closet/statue/toggle()
	return

// Reaching 0 integrity shatters the statue, dusting the trapped mob.
/obj/structure/closet/statue/atom_destruction(damage_flag)
	for(var/mob/M in slot_contents())
		shatter(M)
	return ..()

/obj/structure/closet/statue/attack_generic(mob/user, damage, attacktext, environment_smash)
	if(damage && environment_smash)
		for(var/mob/M in slot_contents())
			shatter(M)

/obj/structure/closet/statue/explosion_contents_severity(severity)
	return severity

/// Overrides closet's interaction_item(): a statue takes weapon hits instead of storing items.
/obj/structure/closet/statue/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	user.do_attack_animation(src)
	act_message(user, src, others = span_danger("%U% strikes %T% with [I]."))
	receive_weapon_hit(I, user)
	return TRUE

/// Overrides closet's interaction_drag(): nothing goes into a statue.
/obj/structure/closet/statue/interaction_drag(mob/user, atom/movable/O, datum/interaction/interaction)
	return INTERACTION_HANDLED_PASS

/obj/structure/closet/statue/relaymove()
	return

/// Overrides closet's interaction_hand(): a statue doesn't open.
/obj/structure/closet/statue/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/structure/closet/statue/verb_toggleopen_effect(mob/user, obj/item/held, datum/interaction/interaction)
	return

APPEARANCE_NONE(/obj/structure/closet/statue)

/obj/structure/closet/statue/proc/shatter(mob/user as mob)
	if (user)
		user.dust()
	dump_contents()
	visible_message(span_warning("[src] shatters!."))
	consume(src)
