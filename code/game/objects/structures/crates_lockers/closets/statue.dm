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
		if(L.buckled)
			L.buckled = 0
			L.anchored = FALSE
		L.forceMove(src)
		L.sdisabilities |= MUTE
		max_integrity = L.get_endurance() + 100
		original_int = L.vitality() * L.get_endurance() + 100
		update_integrity(original_int) //stoning damaged mobs will result in easier to shatter statues
		RegisterSignal(L, COMSIG_LIVING_INJURE, PROC_REF(stasis_block_injury))
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

	START_PROCESSING(SSobj, src)

/obj/structure/closet/statue/process()
	timer--
	if (timer <= 0)
		dump_contents()
		STOP_PROCESSING(SSobj, src)
		qdel(src)

/obj/structure/closet/statue/dump_contents()

	for(var/obj/O in src)
		O.forceMove(get_turf(src))

	for(var/mob/living/M in src)
		M.forceMove(loc) // Might be in a belly
		M.sdisabilities &= ~MUTE
		UnregisterSignal(M, COMSIG_LIVING_INJURE)
		if(get_integrity() < original_int) //any new damage the statue incurred is transfered to the mob
			M.injure(INJURY_BLUNT, original_int - get_integrity(), null, src)
		M.reset_perspective() // Fixes a blackscreen flicker

/obj/structure/closet/statue/Destroy()
	// Release the mob properly (unmuted, unregistered) before the base
	// Destroy() spills the interior.
	dump_contents()
	return ..()

/// Go-go gadget stasis field: the encased mob can't be hurt while it's rock.
/obj/structure/closet/statue/proc/stasis_block_injury(mob/living/source, kind, list/amount_ref, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
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
	for(var/mob/M in src)
		shatter(M)
	return ..()

/obj/structure/closet/statue/attack_generic(mob/user, damage, attacktext, environment_smash)
	if(damage && environment_smash)
		for(var/mob/M in src)
			shatter(M)

/obj/structure/closet/statue/ex_act(severity)
	for(var/mob/M in src)
		M.ex_act(severity)
	deal_damage(DAMAGE_BLAST, 60 / severity)

/obj/structure/closet/statue/attackby(obj/item/I as obj, mob/user as mob)
	user.do_attack_animation(src)
	visible_message(span_danger("[user] strikes [src] with [I]."))
	receive_weapon_hit(I, user)

/obj/structure/closet/statue/MouseDrop_T()
	return

/obj/structure/closet/statue/relaymove()
	return

/obj/structure/closet/statue/attack_hand()
	return

/obj/structure/closet/statue/verb_toggleopen()
	return

/obj/structure/closet/statue/update_icon()
	return

/obj/structure/closet/statue/proc/shatter(mob/user as mob)
	if (user)
		user.dust()
	dump_contents()
	visible_message(span_warning("[src] shatters!."))
	qdel(src)
