
/obj/machinery/gibber
	name = "gibber"
	desc = "The name isn't descriptive enough?"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "grinder"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	req_access = list(ACCESS_KITCHEN,ACCESS_MORGUE)
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 4 SECONDS

	var/operating = 0 //Is it on?
	var/dirty = 0 // Does it need cleaning?
	var/gib_time = 40        // Time from starting until meat appears
	var/gib_throw_dir = WEST // Direction to spit meat and gibs in.

	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 500

//auto-gibs anything that bumps into it
/obj/machinery/gibber/autogibber
	var/tmp/turf/input_plate

/obj/machinery/gibber/autogibber/Initialize(mapload)
	. = ..()
	for(var/i in GLOB.cardinal)
		var/obj/machinery/mineral/input/input_obj = locate( /obj/machinery/mineral/input, get_step(src.loc, i) )
		if(input_obj)
			if(isturf(input_obj.loc))
				rel_set(src, nameof(input_plate), input_obj.loc)
				gib_throw_dir = i
				spent(input_obj)
				break

	if(!input_plate())
		log_world("## MISC a [src] didn't find an input plate.")

/// Sealed occupant slot (C8a, containment.md §10).
/datum/om/relation/slot/occupant/gibber
	holder = /obj/machinery/gibber
	slot_id = OCCUPANT_SLOT_GIBBER
	name = "gibber"
	// The slot IS the occupant: read it with SLOT_ITEM(holder, slot_id).

CAPABILITIES(/obj/machinery/gibber/autogibber)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

/// Something walked into it (the bump action's notice).
/obj/machinery/gibber/autogibber/proc/bumped_into(datum/act/act)
	var/datum/notice/bumped/N = act
	var/atom/A = N.bumper
	if(!input_plate()) return

	if(ismob(A))
		var/mob/M = A

		if(M.loc == input_plate()
		)
			M.forceMove(src)
			M.gib()

/// Appearance reader: which status light the gibber shows.
/obj/machinery/gibber/proc/appearance_gibber_light()
	if(!operable())
		return "off"
	if(!slot_item(OCCUPANT_SLOT_GIBBER))
		return "jam"
	return operating ? "use" : "idle"

/// The look (the draw sweep: from its layers).
/obj/machinery/gibber/draw(datum/look/look)
	..()
	if(dirty == 1)
		look.overlay("grbloody")
	switch("[appearance_gibber_light()]")
		if("jam")
			look.overlay("grjam")
		if("use")
			look.overlay("gruse")
		if("idle")
			look.overlay("gridle")

/obj/machinery/gibber/relaymove(mob/user as mob)
	src.go_out()
	return

CAPABILITIES(/obj/machinery/gibber)
	op("gibber_interaction_hand", hand(), priority(OP_PRIORITY_DEFAULT - 2), ungated(), label("Start gibbing"), needs(req(PROC_REF(can_start_gibbing_holds), because = PROC_REF(can_start_gibbing_refusal))), then(PROC_REF(gibber_interaction_hand)))
	op("gibber_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(can_feed_grab_holds), because = PROC_REF(can_feed_grab_refusal))), then(PROC_REF(gibber_interaction_item)))
	op("gibber_interaction_drag", item(/mob), priority(OP_PRIORITY_DEFAULT - 1), gesture(GESTURE_DRAG), label("Put inside"), then(PROC_REF(gibber_interaction_drag)))
	op("gibber_verb_eject", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Empty Gibber"), needs(req_adjacent(), req_capable()), then(PROC_REF(gibber_verb_eject)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/// Requirement: the gibber isn't already running (an inoperable one is ignored silently by the effect).
/obj/machinery/gibber/proc/can_start_gibbing(mob/user, atom/target, obj/item/held)
	if(operable() && operating) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return "the gibber is locked and running, wait for it to finish"
	return TRUE

/// Requirement: a strong enough grip (only asked of grabs; other items fall through).
/obj/machinery/gibber/proc/can_feed_grab(mob/user, atom/target, obj/item/held)
	var/obj/item/grab/G = held
	if(istype(G) && G.state < 2) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return "you need a better grip to do that"
	return TRUE

/// Old attack_hand.
/// Requirement (was REQ_* can_start_gibbing): the legacy check answers TRUE to pass.
/obj/machinery/gibber/proc/can_start_gibbing_holds(datum/act/op/A)
	var/answer = can_start_gibbing(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_start_gibbing_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/gibber/proc/can_start_gibbing_refusal(datum/act/op/A)
	var/answer = can_start_gibbing(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/gibber/proc/gibber_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return TRUE
	src.startgibbing(user)
	return TRUE

/obj/machinery/gibber/examine()
	. = ..()
	. += "The safety guard is [emagged() ? span_danger("disabled") : "enabled"]."

/obj/machinery/gibber/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	set_emagged(!emagged())
	to_chat(user, span_danger("You [emagged() ? "disable" : "enable"] the gibber safety guard."))
	return OP_OK

/// Old attackby.
/// Requirement (was REQ_* can_feed_grab): the legacy check answers TRUE to pass.
/obj/machinery/gibber/proc/can_feed_grab_holds(datum/act/op/A)
	var/answer = can_feed_grab(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_feed_grab_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/gibber/proc/can_feed_grab_refusal(datum/act/op/A)
	var/answer = can_feed_grab(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/gibber/proc/gibber_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(default_part_replacement(user, W))
		return OP_PASS

	var/obj/item/grab/G = W
	if(!istype(G))
		return OP_DECLINE

	move_into_gibber(user,G?.grab_target())
	// Grab() process should clean up the grab item, no need to del it.
	return OP_PASS

/// Old MouseDrop_T.
/obj/machinery/gibber/proc/gibber_interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/target = A.held
	if(user.stat || user.restrained())
		return TRUE
	move_into_gibber(user,target)
	return TRUE

/obj/machinery/gibber/proc/move_into_gibber(mob/user,mob/living/victim)
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)

	if(occupant)
		to_chat(user, span_danger("The gibber is full, empty it first!"))
		return

	if(operating)
		to_chat(user, span_danger("The gibber is locked and running, wait for it to finish."))
		return

	if(!(iscarbon(victim)) && !(isanimal(victim)) )
		to_chat(user, span_danger("This is not suitable for the gibber!"))
		return

	if(ishuman(victim) && !emagged())
		to_chat(user, span_danger("The gibber safety guard is engaged!"))
		return

	if(victim.abiotic(1))
		to_chat(user, span_danger("Subject may not have abiotic items on."))
		return

	act_message(user, victim, others = span_danger("%U% starts to put %T% into the gibber!"))
	src.add_fingerprint(user)
	task_timed(user, 3 SECONDS, src, src, PROC_REF(stuff_done), list(user, victim))

/obj/machinery/gibber/proc/stuff_done(mob/user, mob/living/victim)
	if(!victim.Adjacent(src) || !user.Adjacent(src) || !victim.Adjacent(user) || src?.slot_item(OCCUPANT_SLOT_GIBBER))
		return
	if(!move_into(src, OCCUPANT_SLOT_GIBBER, victim, user))
		return
	act_message(user, victim, others = span_danger("%U% stuffs %T% into the gibber!"))
	changed(src)

/// Old Empty Gibber verb.
/obj/machinery/gibber/proc/gibber_verb_eject(datum/act/op/A)
	var/mob/user = A.actor
	if (user.stat != 0)
		return TRUE
	src.go_out()
	add_fingerprint(user)
	return TRUE

/obj/machinery/gibber/proc/go_out()
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)
	if(operating || !occupant)
		return
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/O in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		O.forceMove(src.loc)
	slot_remove(occupant, get_turf(src))
	changed(src)
	return

/obj/machinery/gibber/proc/startgibbing(mob/user as mob)
	var/mob/living/occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER)
	if(src.operating)
		return
	if(!occupant)
		visible_message(span_danger("You hear a loud metallic grinding sound."))
		return

	use_power(1000)
	visible_message(span_danger("You hear a loud [HAS_SYNTHETIC_BIOLOGY(occupant) ? "metallic" : "squelchy"] grinding sound."))
	src.operating = 1
	changed(src)

	var/slab_name = occupant.name
	var/slab_count = 2 + occupant.meat_amount
	var/slab_type = occupant.meat_type ? occupant.meat_type : /obj/item/reagent_containers/food/snacks/meat
	var/slab_nutrition = occupant.nutrition / 15

	var/list/byproducts = occupant?.butchery_loot?.Copy()

	if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant
		slab_name = occupant.real_name
		slab_type = HAS_SYNTHETIC_BIOLOGY(H) ? /obj/item/stack/material/steel : H.species.meat_type

	// Small mobs don't give as much nutrition.
	if(issmall(occupant))
		slab_nutrition *= 0.5
	slab_nutrition /= slab_count

	for(var/i=1 to slab_count)
		var/obj/item/reagent_containers/food/snacks/meat/new_meat = new slab_type(src, rand(3,8))
		if(istype(new_meat))
			new_meat.name = "[slab_name] [new_meat.name]"
			new_meat.reagents.add_reagent(REAGENT_ID_NUTRIMENT,slab_nutrition)
			if(occupant.reagents)
				occupant.reagents.trans_to_obj(new_meat, round(occupant.reagents.total_volume/(2 + occupant.meat_amount),1))

	add_attack_logs(user,occupant,"Used [src] to gib")

	occupant.ghostize()

	after(src, gib_time, PROC_REF(finish_gibbing), with = list(byproducts))

/obj/machinery/gibber/proc/finish_gibbing(list/byproducts)
	// The occupant is whoever is still in the slot when the timer fires (a deleted one is simply gone).
	var/mob/living/occupant = slot_item(OCCUPANT_SLOT_GIBBER)
	occupant?.gib()
	occupant = src?.slot_item(OCCUPANT_SLOT_GIBBER) // re-fetch: this runs after a delay, so the slot may have changed since capture
	if(occupant) // gib() may not always hard-delete (e.g. a synthetic's remains): the
		// remains stay physically in the slot, but are no longer "the occupant" --
		// unlink without a ledger move (the remains stay physically where they are).
		om_unlink(occupant, src, /datum/om/relation/slot/occupant/gibber)
	play_sfx(src, SFX_EFFECTS_SPLAT)
	operating = 0
	if(LAZYLEN(byproducts))
		for(var/path in byproducts)
			while(byproducts[path])
				if(prob(min(90,30 * byproducts[path])))
					new path(src)

				byproducts[path] -= 1

	latent_materialize_all() // a walk needs real things (C5)
	for (var/obj/thing in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		// There's a chance that the gibber will fail to destroy or butcher some evidence.
		if(istype(thing,/obj/item/organ) && prob(80))
			var/obj/item/organ/OR = thing
			if(OR.can_butcher(src))
				OR.butcher(src, null, src)	// Butcher it, and add it to our list of things to launch.
			else
				consume(thing)
			continue
		thing.forceMove(get_turf(thing)) // Drop it onto the turf for throwing.
		thing.throw_at(get_edge_target_turf(src,gib_throw_dir),rand(0,3),emagged() ? 100 : 50) // Being pelted with bits of meat and bone would hurt.

	changed(src)

/// the input_plate this refers to (a relation view: null once it is deleted).
/obj/machinery/gibber/autogibber/proc/input_plate() as /turf
	return input_plate
