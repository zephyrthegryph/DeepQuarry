//
// Paper Shredder Machine
//
/obj/machinery/papershredder
	name = "paper shredder"
	desc = "For those documents you don't want seen."
	icon = 'icons/obj/papershredder.dmi'
	icon_state = "shredder-off"
	var/shred_anim = "shredder-shredding"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 200
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	power_channel = EQUIP
	circuit = /obj/item/circuitboard/papershredder
	var/max_paper = 10
	var/paperamount = 0
	var/static/list/shred_amounts = list(
		/obj/item/photo = 1,
		/obj/item/shreddedp = 1,
		/obj/item/paper = 1,
		/obj/item/newspaper = 3,
		/obj/item/card/id = 3,
		/obj/item/paper_bundle = 3,
		)
TRACKED(/obj/machinery/papershredder, paperamount)

CAPABILITIES(/obj/machinery/papershredder)
	climb()

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and redraws for them
/obj/machinery/papershredder/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/papershredder/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/papershredder_empty_into,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/papershredder_shred,
		/datum/interaction/machine_verb/papershredder_empty,
	)
	..()

/datum/interaction/machine_item/papershredder_empty_into
	id = "papershredder_empty_into"
	name = "Empty into"
	category = INTERACTION_CAT_EJECT
	held_type = /obj/item/storage
	effect = /obj/machinery/papershredder/proc/interaction_empty_into

/obj/machinery/papershredder/proc/interaction_empty_into(mob/living/user, obj/item/storage/W, datum/interaction/interaction)
	empty_bin(user, W)
	return TRUE

/datum/interaction/machine_item/papershredder_shred
	id = "papershredder_shred"
	name = "Shred"
	held_type = list(/obj/item/photo, /obj/item/shreddedp, /obj/item/paper, /obj/item/newspaper, /obj/item/card/id, /obj/item/paper_bundle)
	effect = /obj/machinery/papershredder/proc/interaction_shred

/obj/machinery/papershredder/proc/interaction_shred(mob/living/user, obj/item/W, datum/interaction/interaction)
	var/paper_result
	for(var/shred_type in shred_amounts)
		if(istype(W, shred_type))
			paper_result = shred_amounts[shred_type]
	if(paper_result)
		if(!operable())
			return TRUE // Need powah!
		if(paperamount == max_paper)
			to_chat(user, span_warning("\The [src] is full; please empty it before you continue."))
			return TRUE
		if(!consume(W, user))
			return TRUE
		set_paperamount(paperamount + (paper_result))
		play_sfx(src, SFX_ITEMS_PSHRED)
		flick(shred_anim, src)
		if(paperamount > max_paper)
			to_chat(user,span_danger("\The [src] was too full, and shredded paper goes everywhere!"))
			for(var/i=(paperamount-max_paper);i>0;i--)
				var/obj/item/shreddedp/SP = get_shredded_paper()
				SP.forceMove(get_turf(src))
				SP.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),1,5)
			set_paperamount(max_paper)
		return TRUE
	return FALSE

/datum/interaction/machine_verb/papershredder_empty
	id = "papershredder_empty"
	name = "Empty bin"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_ACTOR, /obj/machinery/papershredder/proc/actor_can_empty, "you can't do that right now"), REQ_ON(PRED_TARGET, /obj/machinery/papershredder/proc/has_paper, "it is empty"))
	effect = /obj/machinery/papershredder/proc/interaction_empty

/obj/machinery/papershredder/proc/actor_can_empty(mob/actor, atom/target, obj/item/held)
	return !(actor.stat || actor.restrained() || actor.has_status(STAT_WEAKENED) || actor.has_status(STAT_PARALYZED) || actor.lying || actor.has_status(STAT_STUNNED))

/obj/machinery/papershredder/proc/has_paper(mob/actor, atom/target, obj/item/held)
	return paperamount > 0

/obj/machinery/papershredder/proc/interaction_empty(mob/user, obj/item/held, datum/interaction/interaction)
	empty_bin(user)
	return TRUE

/obj/machinery/papershredder/proc/empty_bin(mob/living/user, obj/item/storage/empty_into)

	// Sanity.
	if(empty_into && !istype(empty_into))
		empty_into = null

	if(empty_into && contents_count(empty_into) >= empty_into.storage_slots)
		to_chat(user, span_notice("\The [empty_into] is full."))
		return

	while(paperamount)
		var/obj/item/shreddedp/SP = get_shredded_paper()
		if(!SP) break
		if(empty_into)
			if(!empty_into.insert_item(SP, user, TRUE))
				break
			if(contents_count(empty_into) >= empty_into.storage_slots)
				break
	if(empty_into)
		if(paperamount)
			to_chat(user, span_notice("You fill \the [empty_into] with as much shredded paper as it will carry."))
		else
			to_chat(user, span_notice("You empty \the [src] into \the [empty_into]."))

	else
		to_chat(user, span_notice("You empty \the [src]."))

/obj/machinery/papershredder/proc/get_shredded_paper()
	if(!paperamount)
		return
	set_paperamount(paperamount - 1)
	return new /obj/item/shreddedp(get_turf(src))

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/papershredder/draw(datum/look/look)
	..()
	look.state("shredder-[operable() ? "on" : "off"]")
	switch("[appearance_fill()]")
		if("0")
			look.overlay("shredder-0")
		if("1")
			look.overlay("shredder-1")
		if("2")
			look.overlay("shredder-2")
		if("3")
			look.overlay("shredder-3")
		if("4")
			look.overlay("shredder-4")
		if("5")
			look.overlay("shredder-5")
	if(panel_open == 1)
		look.overlay("panel_open")

/// Fullness, 0..5.
/obj/machinery/papershredder/proc/appearance_fill()
	return max(0, min(5, FLOOR(paperamount / max_paper * 5, 1)))

//
// Shredded Paper Item
//

/obj/item/shreddedp
	name = "shredded paper"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "shredp"
	throwforce = 0
	w_class = ITEMSIZE_TINY
	throw_range = 3
	throw_speed = 1

CAPABILITIES(/obj/item/shreddedp)
	rolls(ROLL_PIXEL, PIXEL_JITTER(5))
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/shreddedp/proc/roll_color(datum/roller/R)
	return R.chance(65) ? R.choose(list("#BABABA", "#7F7F7F")) : color

DECLARE_INTERACTIONS(/obj/item/shreddedp, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/shreddedp/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/flame/lighter))
		burnpaper(W, user)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/shreddedp/proc/burnpaper(obj/item/flame/lighter/P, mob/user)
	if(user.restrained())
		return
	if(!P.lit)
		to_chat(user, span_warning("\The [P] is not lit."))
		return
	act_message(user, src, MSG_SELF(span_warning("You hold %I% up to %T%, burning it slowly.")), \
		MSG_OTHERS(span_warning("%U% holds %I% up to %T%. It looks like %THEYRE% trying to burn it!")), \
		item = P)
	om_task_start(/datum/om/task/timed/shreddedp_burnpaper, user, src, receiver = src, fail_message = span_warning("You must hold \the [P] steady to burn \the [src]."))

/datum/om/task/timed/shreddedp_burnpaper
	duration = 2 SECONDS
	complete_proc = /obj/item/shreddedp/proc/burnpaper_done

/obj/item/shreddedp/proc/burnpaper_done(datum/om/task/timed/shreddedp_burnpaper/task)
	var/mob/user = task.actor
	act_message(user, src, MSG_SELF(span_danger("You burn right through %T%, turning it to ash. It flutters through the air before settling on the floor in a heap.")), \
		MSG_OTHERS(span_danger("%U% burns right through %T%, turning it to ash. It flutters through the air before settling on the floor in a heap.")))
	FireBurn()

/obj/item/shreddedp/proc/FireBurn()
	var/mob/living/M = loc
	if(istype(M))
		M.drop_from_inventory(src)
	replace_with(src, /obj/effect/decal/cleanable/ash)
