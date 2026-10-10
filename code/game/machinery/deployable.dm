/*
CONTAINS:
Deployable items
*/

/obj/machinery/deployable
	name = "deployable"
	desc = "deployable"
	icon = 'icons/obj/objects.dmi'
	req_access = list(ACCESS_SECURITY)//I'm changing this until these are properly tested./N

/obj/machinery/deployable/barrier
	var/emagged = 0
	name = "deployable barrier"
	desc = "A deployable barrier. Swipe your ID card to lock/unlock it."
	icon = 'icons/obj/objects.dmi'
	anchored = FALSE
	density = TRUE
	icon_state = "barrier0"
	max_integrity = 100
	locked = 0.0

/// The look (the draw sweep: from its layers).
/obj/machinery/deployable/barrier/draw(datum/look/look)
	..()
	switch("[locked]")
		if("0")
			look.state("barrier0")
		if("1")
			look.state("barrier1")

/obj/machinery/deployable/barrier/proc/interaction_swipe_id(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(allowed(user))
		if(emagged < 2.0)
			set_locked(!locked)
			set_anchored(!anchored)
			icon_state = "barrier[locked]"
			if((locked == 1.0) && (emagged < 2.0))
				to_chat(user, "Barrier lock toggled on.")
				return TRUE
			else if((locked == 0.0) && (emagged < 2.0))
				to_chat(user, "Barrier lock toggled off.")
				return TRUE
		else
			fx_sparks(src, 2)
			visible_message(span_warning("BZZzZZzZZzZT"))
			return TRUE
	return TRUE

/obj/machinery/deployable/barrier/proc/interaction_hit(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	switch(W.obj_damage_type())
		if(BURN)
			receive_weapon_hit(W, user, W.force * 0.75, INJURY_BURN)
		if(BRUTE)
			receive_weapon_hit(W, user, W.force * 0.5)
	play_sfx(src, SFX_WEAPONS_SMASH)
	return OP_DECLINE

/obj/machinery/deployable/barrier/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(get_integrity() >= max_integrity && !emagged)
		return OP_OK
	repair_damage(max_integrity)
	set_emagged(FALSE)
	req_access = list(ACCESS_SECURITY)
	act_message(user, src, others = span_warning("%U% repairs %T%!"))
	return OP_OK

// At zero integrity the barrier blows apart.
/obj/machinery/deployable/barrier/atom_destruction(damage_flag)
	explode(FALSE)
	return ..()

CAPABILITIES(/obj/machinery/deployable/barrier)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(barrier_emp))))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE)
	// Two stages (the access lock, then the anchoring); a fully shorted mechanism takes no third card use.
	extend("emag.use", needs(req(PROC_REF(emag_stage_left))))
	extend("emag.subvert", needs(req(PROC_REF(emag_stage_left))))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("swipe_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Swipe ID"), then(PROC_REF(interaction_swipe_id)))
	op("hit", item(/obj/item), hostile(), when(req_on_origin(ORIGIN_CLICK | ORIGIN_MENU, req_stance(I_HURT))), priority(OP_PRIORITY_DEFAULT - 1), label("Hit"), then(PROC_REF(interaction_hit)))

/// Is there an emag stage left to break (emagged 0: the access lock, 1: the anchoring)?
/obj/machinery/deployable/barrier/proc/emag_stage_left(datum/act/A)
	return (emagged < 2) ? null : MSG(emag/already)

/// An EMP may flip the barrier's lock and anchors.
/obj/machinery/deployable/barrier/proc/barrier_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(!operable())
		return HOOK_DECLINE
	if(prob(50/packet.severity))
		set_locked(!locked)
		set_anchored(!anchored)
		icon_state = "barrier[locked]"
	return HOOK_DECLINE

/obj/machinery/deployable/barrier/CanPass(atom/movable/mover, turf/target)//So bullets will fly over and stuff.
	if(istype(mover) && mover.checkpass(PASSTABLE) && !isliving(mover)) // Check if living so teshari can't evade security barriers by pressing W
		return TRUE
	return FALSE

/obj/machinery/deployable/barrier/proc/explode(delete_after = TRUE)

	visible_message(span_danger("[src] blows apart!"))
	var/turf/Tsec = get_turf(src)

/*	var/obj/item/stack/rods/ =*/
	new /obj/item/stack/rods(Tsec)

	fx_sparks(src, 3)

	explosion(src.loc,-1,-1,0)
	if(delete_after && !QDELETED(src))
		destroyed(src, null, "explosion")

/// A sequencer breaks the access lock, a second one the anchoring.
/obj/machinery/deployable/barrier/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(emagged == 0)
		set_emagged(1)
		req_access = null
		req_one_access = null
		to_chat(user, "You break the ID authentication lock on \the [src].")
		fx_sparks(src, 2)
		visible_message(span_warning("BZZzZZzZZzZT"))
	else if(emagged == 1)
		set_emagged(2)
		to_chat(user, "You short out the anchoring mechanism on \the [src].")
		fx_sparks(src, 2)
		visible_message(span_warning("BZZzZZzZZzZT"))
	return OP_OK


/obj/structure/barricade/cutout
	name = "stand-up figure"
	desc = "Some sort of wooden stand-up figure..."
	icon = 'icons/obj/cardboard_cutout.dmi'
	icon_state = "cutout_basic"

	max_integrity = 15 //Weaker than normal barricade
	anchored = FALSE

	var/fake_name = "unknown"
	var/fake_desc = "You have to be closer to examine this creature."
	var/construct_name = "basic cutout"

	var/toppled = FALSE
	var/human_name = TRUE

	var/static/list/cutout_types
	resistance_flags = FLAMMABLE

/obj/structure/barricade/cutout/Initialize(mapload)
	. = ..()
	color = null
	if(human_name)
		fake_name = random_name(pick(list(MALE, FEMALE)))
	name = fake_name
	desc = fake_desc
	if(!cutout_types)
		cutout_types = list()
		var/list/types = typesof(/obj/structure/barricade/cutout)
		for(var/cutout_type in types)
			var/obj/structure/barricade/cutout/pathed_type = cutout_type
			cutout_types[initial(pathed_type.construct_name)] = cutout_type

/obj/structure/barricade/cutout/proc/topple()
	if(toppled)
		return
	toppled = TRUE
	icon_state = "cutout_pushed_over"
	set_density(FALSE)
	name = initial(name)
	desc = initial(desc)
	visible_message(span_warning("[src] topples over!"))

/obj/structure/barricade/cutout/proc/untopple()
	if(!toppled)
		return
	toppled = FALSE
	icon_state = initial(icon_state)
	set_density(TRUE)
	name = fake_name
	desc = fake_desc
	visible_message(span_warning("[src] is uprighted to their proper position."))

/obj/structure/barricade/cutout/on_update_integrity(old_value, new_value)
	. = ..()
	if(!toppled && (new_value < (max_integrity/2)))
		topple()

/// Old attack_hand: stand a toppled cutout back up (behind the structure gate, as before).
/obj/structure/barricade/cutout/proc/cutout_interaction_hand(datum/act/op/A)
	if(!toppled)
		return OP_DECLINE
	untopple()
	return TRUE

/obj/structure/barricade/cutout/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		. += span_notice("... from this distance, they seem to be made of [material.name] ...")

CAPABILITIES(/obj/structure/barricade/cutout)
	op("cutout_interaction_hand", hand(), label("Stand up"), then(PROC_REF(cutout_interaction_hand)))
	// A painter paints it; both paint inputs use the same answer and timed work.
	op("cutout_interaction_item", item(/obj/item/reagent_containers/glass/paint), label("Paint"),
		asks(/datum/prompt/choice, fields = list("title" = "Cutout Painting", "question" = "What would you like to paint the cutout as?", "choices" = nameof(cutout_types), "subject" = computed(PROC_REF(paint_subject)), "ask_flags" = ASK_HELD | ASK_CAPABLE, "timeout" = 0), step = "paint", keeps = HELD | ALIVE),
		needs(req_adjacent()), wait(10 SECONDS), then(PROC_REF(cutout_paint_done)))
	op("cutout_paint_painter", item(/obj/item/floor_painter), label("Paint"),
		asks(/datum/prompt/choice, fields = list("title" = "Cutout Painting", "question" = "What would you like to paint the cutout as?", "choices" = nameof(cutout_types), "subject" = computed(PROC_REF(paint_subject)), "ask_flags" = ASK_HELD | ASK_CAPABLE, "timeout" = 0), step = "paint", keeps = HELD | ALIVE),
		needs(req_adjacent()), wait(10 SECONDS), then(PROC_REF(cutout_paint_done)))

/obj/structure/barricade/cutout/proc/paint_subject(datum/act/op/A)
	return A.held

/obj/structure/barricade/cutout/proc/cutout_paint_done(datum/act/op/A)
	var/picked_type = cutout_types[A.step_value("paint")]
	replace_with(src, picked_type) // Technically heals it too: the new cutout is a fresh one.
	return OP_OK

//Variants
/obj/structure/barricade/cutout/greytide
	icon_state = "cutout_greytide"
	construct_name = "greytide"
/obj/structure/barricade/cutout/clown
	icon_state = "cutout_clown"
	construct_name = "clown"
/obj/structure/barricade/cutout/mime
	icon_state = "cutout_mime"
	construct_name = "mime"
/obj/structure/barricade/cutout/traitor
	icon_state = "cutout_traitor"
	construct_name = "criminal employee"
/obj/structure/barricade/cutout/fluke
	icon_state = "cutout_fluke"
	construct_name = "nuclear operative"
/obj/structure/barricade/cutout/cultist
	icon_state = "cutout_cultist"
	construct_name = "presumed cultist"
/obj/structure/barricade/cutout/servant
	icon_state = "cutout_servant"
	construct_name = "druid"
/obj/structure/barricade/cutout/new_servant
	icon_state = "cutout_new_servant"
	construct_name = "other druid"
/obj/structure/barricade/cutout/viva
	icon_state = "cutout_viva"
	human_name = FALSE
	fake_name = "Unknown"
	construct_name = "advanced greytide"
/obj/structure/barricade/cutout/wizard
	icon_state = "cutout_wizard"
	construct_name = "wizard"
/obj/structure/barricade/cutout/shadowling
	icon_state = "cutout_shadowling"
	human_name = FALSE
	fake_name = "Unknown"
	construct_name = "dark creature"
/obj/structure/barricade/cutout/fukken_xeno
	icon_state = "cutout_fukken_xeno"
	human_name = FALSE
	fake_name = "xenomorph"
	construct_name = "alien"
/obj/structure/barricade/cutout/swarmer
	icon_state = "cutout_swarmer"
	human_name = FALSE
	fake_name = "swarmer"
	construct_name = "robot"
/obj/structure/barricade/cutout/free_antag
	icon_state = "cutout_free_antag"
	construct_name = "hot lizard"
/obj/structure/barricade/cutout/deathsquad
	icon_state = "cutout_deathsquad"
	construct_name = "unknown"
/obj/structure/barricade/cutout/ian
	icon_state = "cutout_ian"
	human_name = FALSE
	fake_name = "corgi"
	construct_name = "dog"
/obj/structure/barricade/cutout/ntsec
	icon_state = "cutout_ntsec"
	construct_name = "nt security"
/obj/structure/barricade/cutout/lusty
	icon_state = "cutout_lusty"
	human_name = FALSE
	fake_name = "xenomorph"
	construct_name = "hot alien"
/obj/structure/barricade/cutout/gondola
	icon_state = "cutout_gondola"
	construct_name = "creature"
/obj/structure/barricade/cutout/monky
	icon_state = "cutout_monky"
	human_name = FALSE
	fake_name = "monkey"
	construct_name = "monkey"
/obj/structure/barricade/cutout/law
	icon_state = "cutout_law"
	human_name = FALSE
	fake_name = "Beepsky"
	construct_name = "lawful robot"

/obj/random/cutout //Random wooden standup figure
	name = "random wooden figure"
	desc = "This is a random wooden figure."
	icon = 'icons/obj/cardboard_cutout.dmi'
	icon_state = "cutout_random"

// Only spawns 20% of the time to avoid being predictable
CAPABILITIES(/obj/random/cutout)
	loot(table = list(loot_types(1, subtypesof(/obj/structure/barricade/cutout))), chance = 20)

/obj/machinery/deployable/barrier/set_emagged(value)
	if(emagged == value)
		return FALSE
	emagged = value
	tracked_bridged_changed(src, "emagged")
	return TRUE
