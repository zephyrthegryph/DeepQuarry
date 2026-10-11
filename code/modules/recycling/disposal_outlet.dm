#define OUTLET_SCREWED 0
#define OUTLET_UNSCREWED 1

// the disposal outlet machine
/obj/structure/disposaloutlet
	name = "disposal outlet"
	desc = "An outlet for the pneumatic disposal system."
	icon = 'icons/obj/pipes/disposal.dmi'
	icon_state = "outlet"
	density = TRUE
	anchored = TRUE
	var/active = FALSE // Code appendix.
	var/tmp/turf/target	// this will be where the output objects are 'thrown' to.
	var/mode = 0
	EXPIRY_DECLARE(start_eject)
	var/eject_range = 3 //Did you know, in TGcode, it's a default of 2 tiles?

/obj/structure/disposaloutlet/Initialize(mapload)
	. = ..()

	update_target()

	var/obj/structure/disposalpipe/trunk/trunk = locate_on(get_turf(src), /obj/structure/disposalpipe/trunk)
	add_disposal_connection()
	observe(src, /datum/notice/disposal_receive, src, then(PROC_REF(on_disposal_receive)))
	if(trunk)
		PUBLISH_LEGACY(src, /datum/notice/disposal_link, trunk)

// it unlinks from its trunk.
/obj/structure/disposaloutlet/on_destroy(force)
	PUBLISH_LEGACY(src, /datum/notice/disposal_unlink)
	..()

CAPABILITIES(/obj/structure/disposaloutlet)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_welder", lit_welder(fuel = 0), needs(req(PROC_REF(welder_refusal), silent = TRUE)), starts(PROC_REF(welder_started)), begins(PROC_REF(welder_begins)), wait(2 SECONDS), then(PROC_REF(welder_act_tool_done)))
	op("use_multitool", tool(TOOL_MULTITOOL), label("Set ejection strength"), needs(req(PROC_REF(config_refusal))), asks(/datum/prompt/number/disposal_outlet_range, fields = list("default" = computed(PROC_REF(range_default))), step = "range"), then(PROC_REF(range_set)))

/// Old attackby.
/obj/structure/disposaloutlet/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!I || !user)
		return OP_PASS
	src.add_fingerprint(user)
	if(mode == OUTLET_SCREWED)
		return OP_DECLINE
	return OP_PASS

/obj/structure/disposaloutlet/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	mode = mode == OUTLET_SCREWED ? OUTLET_UNSCREWED : OUTLET_SCREWED
	to_chat(user, "You [mode == OUTLET_UNSCREWED ? "remove" : "attach"] the screws around the power connection.")
	playsound(src, sounds_of(I).use, 50, 1)
	return OP_OK

/// When the welder does nothing (the click is used up, nothing is said).
/obj/structure/disposaloutlet/proc/welder_refusal(datum/act/op/A)
	return read_once(mode != OUTLET_UNSCREWED) ? "no" : null

/obj/structure/disposaloutlet/proc/welder_started(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 100, TRUE)

/obj/structure/disposaloutlet/proc/welder_begins(datum/act/op/A)
	return msg_text("You start slicing the floorweld off the disposal outlet.", null)

/obj/structure/disposaloutlet/proc/welder_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!src)
		return OP_OK
	to_chat(user, "You sliced the floorweld off the disposal outlet.")
	PUBLISH_LEGACY(src, /datum/notice/disposal_unlink)
	var/obj/structure/disposalconstruct/C = new(src.loc)
	transfer_fingerprints_to(C)
	C.set_dir(dir)
	C.ptype = 7
	C.update()
	C.set_anchored(TRUE)
	C.set_density(TRUE)
	replace_with(src, C)

/// A closed (screwed) outlet's range cannot be set.
/obj/structure/disposaloutlet/proc/config_refusal(datum/act/op/A)
	return read_once(mode) == OUTLET_SCREWED ? "its panel is closed" : null

/obj/structure/disposaloutlet/proc/range_default(datum/act/op/A)
	return eject_range

/// The answered range is set (refused, as config_refusal says, once the panel was closed meanwhile).
/obj/structure/disposaloutlet/proc/range_set(datum/act/op/A)
	var/new_range = A.step_value("range")
	if(isnull(new_range))
		return OP_OK
	SStgui.update_uis(src)
	apply_outlet_range(A.actor, new_range)
	return OP_OK

/datum/prompt/number/disposal_outlet_range
	question = "Input a new ejection distance"
	title = "Set ejection strength"
	default = 3
	min_value = 1
	max_value = 5
	timeout = 0

/datum/prompt/number/disposal_outlet_range/normalize(given)
	return isnum(given) ? given : null

/obj/structure/disposaloutlet/proc/apply_outlet_range(mob/user, new_range)
	eject_range = new_range
	to_chat(user, span_notice("You set the range on the [src] to [new_range] tiles."))
	return ITEM_INTERACT_SUCCESS


/// Hooked on our own disposal_receive event.
/obj/structure/disposaloutlet/proc/on_disposal_receive(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	var/datum/notice/disposal_receive/event = A
	packet_expel(source, event.items, event.gas)

/obj/structure/disposaloutlet/proc/packet_expel(datum/source, list/received_items, datum/gas_mixture/gas)
	SHOULD_NOT_SLEEP(TRUE)

	flick("outlet-open", src)
	if(ELAPSED(src, start_eject, CLOCK_WORLD) > 3 SECONDS)
		EXPIRY_STAMP(src, start_eject, CLOCK_WORLD)
		play_sfx(src, SFX_MACHINES_WARNING_BUZZER)
		after(src, 2 SECONDS, PROC_REF(expel_contents), with = list(received_items, gas, TRUE), keeps_dead = TRUE)
	else
		after(src, 2 SECONDS, PROC_REF(expel_contents), with = list(received_items, gas))

/obj/structure/disposaloutlet/proc/expel_contents(list/ejected_items, datum/gas_mixture/gas, playsound = FALSE)
	if(playsound)
		play_sfx(src, SFX_MACHINES_HISS)

	var/turf/T = get_turf(src)

	for(var/atom/movable/AM in ejected_items)
		AM.forceMove(T)
		AM.pipe_eject(dir)
		AM.throw_at(target(), eject_range, 1)

	T.assume_air(gas)

/obj/structure/disposaloutlet/set_dir(newdir)
	. = ..()
	update_target()

/obj/structure/disposaloutlet/proc/update_target()
	rel_set(src, nameof(target), get_ranged_target_turf(src, dir, 10))

#undef OUTLET_SCREWED
#undef OUTLET_UNSCREWED

/// this will be where the output objects are 'thrown' to. (a relation view: it reads null once the target is deleted).
/obj/structure/disposaloutlet/proc/target() as /turf
	return target
