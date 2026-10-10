/obj/structure/closet/statue
	name = "statue"
	desc = "An incredibly lifelike marble carving"
	icon = 'icons/obj/statue.dmi'
	icon_state = "human_male"
	density = TRUE
	anchored = TRUE
	sealable = FALSE
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE
	closet_appearance = null
	// The statue starts at the encased mob's remaining wellness (vitality * endurance) + 100
	// integrity (set in Initialize). Structural damage taken while petrified is transferred
	// back to the mob on release; meanwhile the stasis field cancels all injury to the mob.
	max_integrity = 100
	/// Integrity the statue started at; damage below this is dealt to the mob on release.
	var/original_int = 100
	var/timer = 240 //eventually the person will be freed

/// The sprite of the encased mob's shape ("human_female", "monkey", "corgi"), or null for the mapped one.
/obj/structure/closet/statue/var/statue_shape

/// How long after init the petrification wears off (after_init()).
/obj/structure/closet/statue/var/release_delay = 0

/// The mob turned to stone (its constructor param, dropped after init).
/obj/structure/closet/statue/var/tmp/mob/living/statue_of

// ALLOW(init/INSTANCE_STATE): a statue holds the mob it petrifies, shielded from harm, until it releases them
/obj/structure/closet/statue/Initialize(mapload)
	. = ..()
	var/mob/living/L = statue_of
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
		observe(L, /datum/act/injure, src, instead(when(PROC_REF(stasis_holds))))
		if(ishuman(L))
			name = "statue of [L.name]"
			if(L.gender == "female")
				statue_shape = "human_female"
		else if(L.isMonkey())
			name = "statue of a monkey"
			statue_shape = "monkey"
		else if(iscorgi(L))
			name = "statue of a corgi"
			statue_shape = "corgi"
			desc = "If it takes forever, I will wait for you..."

	if(!found_target) //meaning if the statue didn't find a valid target
		return INITIALIZE_HINT_QDEL
	if(statue_shape)
		changed(src)

	release_delay = timer * 2 SECONDS // the old countdown: one per 2 s step (after_init())

/// The petrification wears off (its timer): the statue frees whoever is inside.
/obj/structure/closet/statue/proc/release(datum/act/A)
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
		unobserve(M, /datum/act/injure, src)
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
/obj/structure/closet/statue/proc/stasis_holds(datum/act/injure/hit)
	var/mob/living/victim = hit.target
	return victim.loc == src

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

/obj/structure/closet/statue/relaymove()
	return

// A statue is a closet that never opens: nothing goes into it, the hand does nothing, and anything held strikes it (it takes weapon hits instead of storing items).
CAPABILITIES(/obj/structure/closet/statue)
	when(nameof(release_delay), after_init(nameof(release_delay), then(PROC_REF(release))))
	configure(blast_contents(shield = 0)) // stone holds nothing back from the one petrified inside
	without("door")
	without("stuff")
	without("stuff_grab")
	without("set_down")
	without("empty_basket")
	without("melee_hit")
	op("statue_strike", item(/obj/item), label("Strike"), priority(OP_PRIORITY_PART + 20), then(PROC_REF(statue_struck)))
	param(nameof(statue_of), pos = 1, keep = FALSE)

/// A held thing strikes the statue.
/obj/structure/closet/statue/proc/statue_struck(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	user.do_attack_animation(src)
	act_message(user, src, others = span_danger("%U% strikes %T% with [I]."))
	receive_weapon_hit(I, user)
	return OP_OK

/// A statue keeps its mapped sprite (the encased mob's shape), with none of a closet's door states.
/obj/structure/closet/statue/closet_look(datum/look/look)
	if(statue_shape)
		look.state(statue_shape)

/obj/structure/closet/statue/proc/shatter(mob/user as mob)
	if (user)
		user.dust()
	dump_contents()
	visible_message(span_warning("[src] shatters!."))
	consume(src)
