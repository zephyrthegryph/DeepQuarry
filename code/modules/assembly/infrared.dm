//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

MATERIAL_MIX(/obj/item/assembly/infra, list(MAT_STEEL = 1000, MAT_GLASS = 500))
/obj/item/assembly/infra
	name = "infrared emitter"
	desc = "Emits a visible or invisible beam and is triggered when the beam is interrupted."
	icon_state = "infrared"

	wires_type = WIRE_PULSE

	secured = 0

	var/visible = 0
	var/list/i_beams = null

CAPABILITIES(/obj/item/assembly/infra)
	owns_many(nameof(i_beams))
	interface("AssemblyInfrared", state = nameof(GLOB.tgui_deep_inventory_state))
	without("ui_open")
	op("state", ui_act("state"), then(PROC_REF(ui_act_state)))
	op("visible", ui_act("visible"), then(PROC_REF(ui_act_visible)))
	rotatable()

OM_FIELD(/obj/item/assembly/infra, on, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE_ALL(/obj/item/assembly/infra, PERIODIC_SLOW, list("secured", "on"))

/obj/item/assembly/infra/activate()
	if(!..())
		return FALSE
	set_on(!on)
	if(!on)
		QDEL_LIST_NULL(i_beams)
	update_icon()
	return TRUE

/obj/item/assembly/infra/toggle_secure()
	set_secured(!secured)
	if(!secured)
		toggle_state(FALSE)
	update_icon()
	return secured

/obj/item/assembly/infra/proc/toggle_state(picked)
	if(!isnull(picked))
		set_on(picked)
	else
		set_on(!on)

	if(!secured || !on)
		QDEL_LIST_NULL(i_beams)
	return on

DECLARE_APPEARANCE_PROC(/obj/item/assembly/infra, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/assembly/infra/appearance_overlays()
	. = list()
	LAZYCLEARLIST(attached_overlays)
	if(on)
		. += "infrared_on"
		LAZYADD(attached_overlays, "infrared_on")

	if(holder())
		holder().update_icon()

/obj/item/assembly/infra/periodic_step()
	if(!i_beams && (istype(loc, /turf) || (holder() && istype(holder().loc, /turf))))
		create_beams()

/obj/item/assembly/infra/proc/create_beams(limit = 8)
	var/current_spot = get_turf(src)
	for(var/i = 1 to limit)
		var/obj/effect/beam/i_beam/I = new /obj/effect/beam/i_beam(current_spot)
		rel_set(I, nameof(I.master), src)
		I.set_density(TRUE)
		I.set_dir(dir)
		if(!step(I, I.dir)) //Try to take a step in that direction
			return //Couldn't, oh well, we hit a wall or something. Beam should qdel itself in it's Bump().
		I.set_density(FALSE)
		rel_add(src, nameof(i_beams), I)
		I.visible = visible

/// A subtype adding to an ancestor's compact specs uses declare_interactions() (the proven
/// chain, ..() and all) and builds its own entry directly with dq_interaction_from_spec() -
/// see doc/rewrite/interactions.md §5a for why get_interactions() itself doesn't chain here.
/obj/item/assembly/infra/declare_interactions(list/into)
	into += dq_interaction_from_spec(type, INTERACT_HAND(null, PROC_REF(interaction_hand)))
	..()

/// Old attack_hand: clear the beams before falling through to normal pickup.
/obj/item/assembly/infra/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	QDEL_LIST_NULL(i_beams)
	return FALSE

/obj/item/assembly/infra/Move()
	var/t = dir
	. = ..()
	set_dir(t)

/obj/item/assembly/infra/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	QDEL_LIST_NULL(i_beams)

/obj/item/assembly/infra/holder_movement()
	if(!holder())
		return FALSE
	QDEL_LIST_NULL(i_beams)
	return TRUE

/obj/item/assembly/infra/proc/trigger_beam()
	if(!COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	pulse(0)
	QDEL_LIST_NULL(i_beams) //They will get recreated next process() if the situation is still appropriate
	if(!holder())
		visible_message("[icon2html(src,viewers(src))] *beep* *beep*")

/obj/item/assembly/infra/ui_prepare(mob/user, datum/tgui/ui)
	if(!secured)
		to_chat(user, span_warning("[src] is unsecured!"))
		return FALSE
	return TRUE

/obj/item/assembly/infra/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on
	data["visible"] = visible
	return data

/obj/item/assembly/infra/proc/ui_act_state(datum/act/op/A)
	toggle_state()
	return TRUE

/obj/item/assembly/infra/proc/ui_act_visible(datum/act/op/A)
	visible = !visible
	for(var/obj/effect/beam/i_beam/I as anything in i_beams)
		I.visible = visible
		CHECK_TICK
	return TRUE

/***************************IBeam*********************************/

/obj/effect/beam/i_beam
	name = "i beam"
	icon = 'icons/obj/projectiles.dmi'
	icon_state = "ibeam"
	var/tmp/obj/item/assembly/infra/master
	var/visible = 0
	anchored = TRUE

/obj/effect/beam/i_beam/proc/hit()
	master()?.trigger_beam()
	consume(src)

/obj/effect/beam/i_beam/proc/i_beam_step(datum/act/timer/A)
	if(loc?.density || !master())
		consume(src)
		return

/obj/effect/beam/i_beam/Bump()
	consume(src)

CAPABILITIES(/obj/effect/beam/i_beam)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	every(2 SECONDS, then(PROC_REF(i_beam_step)))

/// Something walked into it (the bump action's notice).
/obj/effect/beam/i_beam/proc/bumped_into(datum/act/A)
	hit()

/obj/effect/beam/i_beam/Crossed(atom/movable/AM)
	if(AM.is_incorporeal())
		return
	if(istype(AM, /obj/effect/beam))
		return
	hit()

/// the master this refers to (a relation view: null once it is deleted).
/obj/effect/beam/i_beam/proc/master() as /obj/item/assembly/infra
	return master

