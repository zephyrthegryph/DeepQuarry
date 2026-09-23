/**
 * Vehicle assembly construction graphs (doc/rewrite/interactions.md §10).
 *
 * Each `/obj/item/vehicle_assembly` builds up through a sequence of item and
 * tool steps, tracked by `build_stage` (the graph's `state_var`). The last
 * step (a wrench or a screwdriver) turns the assembly into the finished
 * vehicle and moves the installed cell across.
 */

/obj/item/vehicle_assembly
	name = "vehicle assembly"
	desc = "The frame of some vehicle."
	icon = 'icons/obj/vehicles_64x64.dmi'
	icon_state = "quad-frame"
	item_state = "buildpipe"

	density = TRUE
	slowdown = 10 //It's a vehicle frame, what do you expect?
	w_class = ITEMSIZE_HUGE

	var/build_stage = 0
	var/obj/item/cell/cell = null

/obj/item/vehicle_assembly/Initialize(mapload)
	. = ..()
	icon_state = "[initial(icon_state)][build_stage]"
	update_icon()

/// Sets the numbered icon_state for `stage` and, when given, the display name.
/obj/item/vehicle_assembly/proc/set_build_visuals(stage, new_name)
	if(new_name)
		name = new_name
	if(isnum(stage))
		icon_state = "[initial(icon_state)][stage]"

/datum/construction_graph/vehicle
	state_var = "build_stage"

/datum/construction_graph/vehicle/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	if(!QDELETED(target))
		target.update_icon()

/datum/interaction/construction/vehicle
	tool_volume = 50

/*
 * Quadbike and trailer.
 */

/obj/item/vehicle_assembly/quadbike
	name = "all terrain vehicle assembly"
	desc = "The frame of an ATV."
	icon_state = "quad-frame"
	pixel_x = -16
	construction_graph = /datum/construction_graph/vehicle/quadbike

/datum/construction_graph/vehicle/quadbike
	id = "quadbike"
	states = list(0, 1, 2, 3, 4, 5, 6, 7)
	initial_states = list(0)
	edge_types = list(
		/datum/interaction/construction/vehicle/quadbike/tires,
		/datum/interaction/construction/vehicle/quadbike/lights,
		/datum/interaction/construction/vehicle/quadbike/controls,
		/datum/interaction/construction/vehicle/quadbike/to_trailer,
		/datum/interaction/construction/vehicle/quadbike/wire,
		/datum/interaction/construction/vehicle/quadbike/power,
		/datum/interaction/construction/vehicle/quadbike/motor,
		/datum/interaction/construction/vehicle/quadbike/reinforce,
		/datum/interaction/construction/vehicle/quadbike/finish_wrench,
		/datum/interaction/construction/vehicle/quadbike/finish_screwdriver,
	)

/datum/interaction/construction/vehicle/quadbike

/datum/interaction/construction/vehicle/quadbike/tires
	from_state = 0
	to_state = 1
	step_text = "add tires to it"
	item_type = /obj/item/stack/material/plastic
	item_amount = 8
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to add tires to %TARGET%."

/datum/interaction/construction/vehicle/quadbike/tires/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.set_build_visuals(after, "wheeled [initial(assembly.name)]")
	to_chat(actor, span_notice("You add tires to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/lights
	from_state = 1
	to_state = 2
	step_text = "add the lights"
	item_type = /obj/item/stock_parts/console_screen
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/quadbike/lights/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the lights to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/controls
	from_state = 2
	to_state = 3
	step_text = "add the control system"
	item_type = /obj/item/stock_parts/spring
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/quadbike/controls/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the control system to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/to_trailer
	from_state = 2
	to_state = CONSTRUCTION_DONE
	step_text = "convert it into a trailer"
	item_type = /obj/item/stack/material/steel
	item_amount = 5
	item_use = CONSTRUCTION_ITEM_USE
	duration = 8 SECONDS
	tool_scaled = FALSE

/datum/interaction/construction/vehicle/quadbike/to_trailer/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	var/obj/item/vehicle_assembly/quadtrailer/trailer = new(assembly)
	trailer.forceMove(get_turf(assembly))
	trailer.build_stage = 1
	trailer.set_build_visuals(1, "framed [initial(trailer.name)]")
	to_chat(actor, span_notice("You convert \the [assembly] into \the [trailer]."))
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE

/datum/interaction/construction/vehicle/quadbike/wire
	from_state = 3
	to_state = 4
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/vehicle/quadbike/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.set_build_visuals(after, "wired [initial(assembly.name)]")
	to_chat(actor, span_notice("You wire \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/power
	from_state = 4
	to_state = 5
	step_text = "add the power supply"
	item_type = /obj/item/cell
	item_use = CONSTRUCTION_ITEM_INSERT

/datum/interaction/construction/vehicle/quadbike/power/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.cell = held
	assembly.set_build_visuals(after, "powered [initial(assembly.name)]")
	to_chat(actor, span_notice("You add the power supply to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/motor
	from_state = 5
	to_state = 6
	step_text = "add the motor"
	item_type = /obj/item/stock_parts/motor
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/quadbike/motor/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the motor to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/reinforce
	from_state = 6
	to_state = 7
	step_text = "add reinforcement"
	item_type = /obj/item/stack/material/plasteel
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to add reinforcement to %TARGET%."

/datum/interaction/construction/vehicle/quadbike/reinforce/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	assembly.set_build_visuals(after, "reinforced [initial(assembly.name)]")
	to_chat(actor, span_notice("You add reinforcement to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/quadbike/finish
	from_state = 7
	to_state = CONSTRUCTION_DONE
	step_text = "finish it"
	duration = 2 SECONDS
	tool_scaled = FALSE
	start_self = "You begin your finishing touches on %TARGET%."

/datum/interaction/construction/vehicle/quadbike/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/assembly = target
	playsound(assembly, held.usesound, 30, TRUE)
	var/obj/vehicle/train/engine/quadbike/built/product = new(assembly)
	to_chat(actor, span_notice("You finish \the [product]"))
	product.loc = get_turf(assembly)
	product.cell = assembly.cell
	assembly.cell.forceMove(product)
	assembly.cell = null
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE

/datum/interaction/construction/vehicle/quadbike/finish_wrench
	parent_type = /datum/interaction/construction/vehicle/quadbike/finish
	tool = TOOL_WRENCH

/datum/interaction/construction/vehicle/quadbike/finish_screwdriver
	parent_type = /datum/interaction/construction/vehicle/quadbike/finish
	tool = TOOL_SCREWDRIVER

/obj/item/vehicle_assembly/quadtrailer
	name = "all terrain trailer"
	desc = "The frame of a small trailer."
	icon_state = "quadtrailer-frame"
	pixel_x = -16
	construction_graph = /datum/construction_graph/vehicle/quadtrailer

/datum/construction_graph/vehicle/quadtrailer
	id = "quadtrailer"
	states = list(0, 1, 2)
	initial_states = list(0)
	edge_types = list(
		/datum/interaction/construction/vehicle/quadtrailer/frame,
		/datum/interaction/construction/vehicle/quadtrailer/wire,
		/datum/interaction/construction/vehicle/quadtrailer/finish,
	)

/datum/interaction/construction/vehicle/quadtrailer/frame
	from_state = 0
	to_state = 1
	step_text = "assemble it from a spare quadbike frame"
	item_type = /obj/item/vehicle_assembly/quadbike
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/quadtrailer/frame/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadbike/quad = held
	var/obj/item/vehicle_assembly/quadtrailer/trailer = target
	if(quad.build_stage > 2)
		to_chat(actor, span_notice("\The [quad] is too advanced to be of use with \the [trailer]"))
		return FALSE
	trailer.set_build_visuals(after, "framed [initial(trailer.name)]")
	return TRUE

/datum/interaction/construction/vehicle/quadtrailer/wire
	from_state = 1
	to_state = 2
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/vehicle/quadtrailer/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = target
	trailer.set_build_visuals(after, "wired [initial(trailer.name)]")
	to_chat(actor, span_notice("You wire \the [trailer]."))
	return TRUE

/datum/interaction/construction/vehicle/quadtrailer/finish
	from_state = 2
	to_state = CONSTRUCTION_DONE
	step_text = "close it up"
	tool = TOOL_SCREWDRIVER

/datum/interaction/construction/vehicle/quadtrailer/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = target
	to_chat(actor, span_notice("You close up \the [trailer]."))
	var/obj/vehicle/train/trolley/trailer/product = new(trailer)
	product.loc = get_turf(trailer)
	actor.drop_from_inventory(trailer)
	qdel(trailer)
	return TRUE

/*
 * Space bike.
 */

/obj/item/vehicle_assembly/spacebike
	name = "vehicle assembly"
	desc = "The frame of some vehicle."
	icon = 'icons/obj/bike.dmi'
	icon_state = "bike-frame"

	pixel_x = 0
	construction_graph = /datum/construction_graph/vehicle/spacebike

/datum/construction_graph/vehicle/spacebike
	id = "spacebike"
	states = list(0, 1, 2, 3, 4, 5, 6)
	initial_states = list(0)
	edge_types = list(
		/datum/interaction/construction/vehicle/spacebike/jetpack,
		/datum/interaction/construction/vehicle/spacebike/wire,
		/datum/interaction/construction/vehicle/spacebike/seat,
		/datum/interaction/construction/vehicle/spacebike/lights,
		/datum/interaction/construction/vehicle/spacebike/controls,
		/datum/interaction/construction/vehicle/spacebike/power,
		/datum/interaction/construction/vehicle/spacebike/finish_wrench,
		/datum/interaction/construction/vehicle/spacebike/finish_screwdriver,
	)

/datum/interaction/construction/vehicle/spacebike/jetpack
	from_state = 0
	to_state = 1
	step_text = "add a jetpack"
	item_type = list(/obj/item/tank/jetpack, /obj/item/borg/upgrade/advanced/jetpack)
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/spacebike/jetpack/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	assembly.set_build_visuals(after)
	return TRUE

/datum/interaction/construction/vehicle/spacebike/wire
	from_state = 1
	to_state = 2
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/vehicle/spacebike/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	assembly.set_build_visuals(after, "wired [initial(assembly.name)]")
	to_chat(actor, span_notice("You wire \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/spacebike/seat
	from_state = 2
	to_state = 3
	step_text = "add a seat"
	item_type = /obj/item/stack/material/plastic
	item_amount = 3
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to add a seat to %TARGET%."

/datum/interaction/construction/vehicle/spacebike/seat/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	assembly.set_build_visuals(after, "seated [initial(assembly.name)]")
	to_chat(actor, span_notice("You add a seat to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/spacebike/lights
	from_state = 3
	to_state = 4
	step_text = "add the lights"
	item_type = /obj/item/stock_parts/console_screen
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/spacebike/lights/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the lights to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/spacebike/controls
	from_state = 4
	to_state = 5
	step_text = "add the control system"
	item_type = /obj/item/stock_parts/spring
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/spacebike/controls/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the control system to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/spacebike/power
	from_state = 5
	to_state = 6
	step_text = "add the power supply"
	item_type = /obj/item/cell
	item_use = CONSTRUCTION_ITEM_INSERT

/datum/interaction/construction/vehicle/spacebike/power/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	assembly.cell = held
	assembly.set_build_visuals(after, "powered [initial(assembly.name)]")
	to_chat(actor, span_notice("You add the power supply to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/spacebike/finish
	from_state = 6
	to_state = CONSTRUCTION_DONE
	step_text = "finish it"
	duration = 2 SECONDS
	tool_scaled = FALSE
	start_self = "You begin your finishing touches on %TARGET%."

/datum/interaction/construction/vehicle/spacebike/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/spacebike/assembly = target
	playsound(assembly, held.usesound, 30, TRUE)
	var/obj/vehicle/bike/built/product = new(assembly)
	to_chat(actor, span_notice("You finish \the [product]"))
	product.loc = get_turf(assembly)
	product.cell = assembly.cell
	assembly.cell.forceMove(product)
	assembly.cell = null
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE

/datum/interaction/construction/vehicle/spacebike/finish_wrench
	parent_type = /datum/interaction/construction/vehicle/spacebike/finish
	tool = TOOL_WRENCH

/datum/interaction/construction/vehicle/spacebike/finish_screwdriver
	parent_type = /datum/interaction/construction/vehicle/spacebike/finish
	tool = TOOL_SCREWDRIVER

/*
 * Snowmobile.
 */

/obj/item/vehicle_assembly/snowmobile
	name = "snowmobile assembly"
	desc = "The frame of a snowmobile."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "snowmobile-frame"
	construction_graph = /datum/construction_graph/vehicle/snowmobile

/datum/construction_graph/vehicle/snowmobile
	id = "snowmobile"
	states = list(0, 1, 2, 3, 4, 5, 6, 7)
	initial_states = list(0)
	edge_types = list(
		/datum/interaction/construction/vehicle/snowmobile/treads,
		/datum/interaction/construction/vehicle/snowmobile/lights,
		/datum/interaction/construction/vehicle/snowmobile/controls,
		/datum/interaction/construction/vehicle/snowmobile/wire,
		/datum/interaction/construction/vehicle/snowmobile/power,
		/datum/interaction/construction/vehicle/snowmobile/motor,
		/datum/interaction/construction/vehicle/snowmobile/reinforce,
		/datum/interaction/construction/vehicle/snowmobile/finish_wrench,
		/datum/interaction/construction/vehicle/snowmobile/finish_screwdriver,
	)

/datum/interaction/construction/vehicle/snowmobile/treads
	from_state = 0
	to_state = 1
	step_text = "add treads to it"
	item_type = /obj/item/stack/material/steel
	item_amount = 6
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to add treads to %TARGET%."

/datum/interaction/construction/vehicle/snowmobile/treads/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.set_build_visuals(after, "tracked [initial(assembly.name)]")
	to_chat(actor, span_notice("You add treads to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/lights
	from_state = 1
	to_state = 2
	step_text = "add the lights"
	item_type = /obj/item/stock_parts/console_screen
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/snowmobile/lights/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the lights to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/controls
	from_state = 2
	to_state = 3
	step_text = "add the control system"
	item_type = /obj/item/stock_parts/spring
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/snowmobile/controls/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the control system to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/wire
	from_state = 3
	to_state = 4
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/vehicle/snowmobile/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.set_build_visuals(after, "wired [initial(assembly.name)]")
	to_chat(actor, span_notice("You wire \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/power
	from_state = 4
	to_state = 5
	step_text = "add the power supply"
	item_type = /obj/item/cell
	item_use = CONSTRUCTION_ITEM_INSERT

/datum/interaction/construction/vehicle/snowmobile/power/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.cell = held
	assembly.set_build_visuals(after, "powered [initial(assembly.name)]")
	to_chat(actor, span_notice("You add the power supply to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/motor
	from_state = 5
	to_state = 6
	step_text = "add the motor"
	item_type = /obj/item/stock_parts/motor
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/vehicle/snowmobile/motor/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.set_build_visuals(after)
	to_chat(actor, span_notice("You add the motor to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/reinforce
	from_state = 6
	to_state = 7
	step_text = "add reinforcement"
	item_type = /obj/item/stack/material/plasteel
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to add reinforcement to %TARGET%."

/datum/interaction/construction/vehicle/snowmobile/reinforce/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	assembly.set_build_visuals(after, "reinforced [initial(assembly.name)]")
	to_chat(actor, span_notice("You add reinforcement to \the [assembly]."))
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/finish
	from_state = 7
	to_state = CONSTRUCTION_DONE
	step_text = "finish it"
	duration = 2 SECONDS
	tool_scaled = FALSE
	start_self = "You begin your finishing touches on %TARGET%."

/datum/interaction/construction/vehicle/snowmobile/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/vehicle_assembly/snowmobile/assembly = target
	playsound(assembly, held.usesound, 30, TRUE)
	var/obj/vehicle/train/engine/quadbike/snowmobile/built/product = new(assembly)
	to_chat(actor, span_notice("You finish \the [product]"))
	product.loc = get_turf(assembly)
	product.cell = assembly.cell
	assembly.cell.forceMove(product)
	assembly.cell = null
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE

/datum/interaction/construction/vehicle/snowmobile/finish_wrench
	parent_type = /datum/interaction/construction/vehicle/snowmobile/finish
	tool = TOOL_WRENCH

/datum/interaction/construction/vehicle/snowmobile/finish_screwdriver
	parent_type = /datum/interaction/construction/vehicle/snowmobile/finish
	tool = TOOL_SCREWDRIVER
