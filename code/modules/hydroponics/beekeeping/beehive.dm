/obj/machinery/beehive
	name = "beehive"
	icon = 'icons/obj/beekeeping.dmi'
	icon_state = "beehive"
	density = TRUE
	anchored = TRUE

	var/closed = 0
	var/honeycombs = 0 // Percent
	var/list/frames	// List of frames inside.
	var/maxFrames = 5
TRACKED(/obj/machinery/beehive, honeycombs)

/// Percent.
OM_FIELD(/obj/machinery/beehive, bee_count, 0, CHANGE_MACHINE_SETTINGS)
/// Timer (machine steps).
OM_FIELD(/obj/machinery/beehive, smoked, 0, CHANGE_MACHINE_SETTINGS)
/// Bees inside or smoke still clearing: the hive has something to tick.
OM_DERIVE_FIELD(/obj/machinery/beehive, hive_active, list("bee_count", "smoked"))
/obj/machinery/beehive/proc/hive_active()
	return bee_count || smoked

CAPABILITIES(/obj/machinery/beehive)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(hive_active), wakes_on = list(nameof(bee_count), nameof(smoked)))
	climb()

/obj/machinery/beehive/draw(datum/look/look)
	..()
	look.state("beehive")
	if(closed)
		look.overlay("lid")
	if(length(frames))
		look.overlay("empty[length(frames)]")
	if(honeycombs >= 100)
		look.overlay("full[round(honeycombs / 100)]")
	if(!smoked)
		switch(bee_count)
			if(1 to 40)
				look.overlay("bees1")
			if(41 to 80)
				look.overlay("bees2")
			if(81 to 100)
				look.overlay("bees3")

/obj/machinery/beehive/examine(mob/user)
	. = ..()
	if(!closed)
		. += "The lid is open."

/obj/machinery/beehive/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/beehive_smoke,
		/datum/interaction/machine_item/beehive_load_frame,
		/datum/interaction/machine_item/beehive_bee_pack,
		/datum/interaction/machine_item/beehive_scan,
		/datum/interaction/machine_hand/ungated/beehive_harvest,
	)
	..()

/datum/interaction/machine_item/beehive_smoke
	id = "beehive_smoke"
	name = "Smoke bees"
	held_type = /obj/item/bee_smoker
	also_requires = list(REQ_FIELD_NOT("closed", "you need to open it with a crowbar before smoking the bees"))
	effect = /obj/machinery/beehive/proc/interaction_beehive_smoke

/obj/machinery/beehive/proc/interaction_beehive_smoke(mob/user, obj/item/held, datum/interaction/interaction)
	act_message(user, src, MSG_SELF(span_notice("You smoke the bees in %T%.")), MSG_OTHERS(span_notice("%U% smokes the bees in %T%.")))
	set_smoked(30)
	changed(src)
	return TRUE

/datum/interaction/machine_item/beehive_load_frame
	id = "beehive_load_frame"
	name = "Load frame"
	held_type = /obj/item/honey_frame
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/beehive/proc/can_load_frame))
	effect = /obj/machinery/beehive/proc/interaction_beehive_load_frame

/// Requirement: TRUE, or why this frame can't go in.
/obj/machinery/beehive/proc/can_load_frame(mob/user, atom/target, obj/item/honey_frame/held)
	if(closed)
		return "you need to open \the [src] with a crowbar before inserting \the [held]"
	if(length(frames) >= maxFrames)
		return "there is no place for an another frame"
	if(held.honey)
		return "\The [held] is full with beeswax and honey, empty it in the extractor first"
	return TRUE

/obj/machinery/beehive/proc/interaction_beehive_load_frame(mob/user, obj/item/honey_frame/held, datum/interaction/interaction)
	act_message(user, src, MSG_SELF(span_notice("You load %I% into %T%.")), MSG_OTHERS(span_notice("%U% loads %I% into %T%.")), item = held)
	changed(src)
	user.drop_from_inventory(held)
	held.forceMove(src)
	rel_add(src, nameof(frames), held)
	return TRUE

/datum/interaction/machine_item/beehive_bee_pack
	id = "beehive_bee_pack"
	name = "Move bees"
	held_type = /obj/item/bee_pack
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/beehive/proc/can_move_bees))
	effect = /obj/machinery/beehive/proc/interaction_beehive_bee_pack

/// Requirement: TRUE, or why the bees can't be moved in or split out.
/obj/machinery/beehive/proc/can_move_bees(mob/user, atom/target, obj/item/bee_pack/held)
	if(held.full && bee_count)
		return "\The [src] already has bees inside"
	if(!held.full && bee_count < 90)
		return "\The [src] is not ready to split"
	if(!held.full && !smoked)
		return "smoke \the [src] first"
	if(closed)
		return "you need to open \the [src] with a crowbar before moving the bees"
	return TRUE

/obj/machinery/beehive/proc/interaction_beehive_bee_pack(mob/user, obj/item/bee_pack/held, datum/interaction/interaction)
	if(held.full)
		act_message(user, src, MSG_SELF(span_notice("You put the queen and the bees from %I% into %T%.")), \
			MSG_OTHERS(span_notice("%U% puts the queen and the bees from %I% into %T%.")), \
			item = held)
		set_bee_count(20)
		held.empty()
	else
		act_message(user, src, MSG_SELF(span_notice("You put bees and larvae from %T% into %I%.")), \
			MSG_OTHERS(span_notice("%U% puts bees and larvae from %T% into %I%.")), \
			item = held)
		set_bee_count(bee_count / 2)
		held.fill()
	changed(src)
	return TRUE

/datum/interaction/machine_item/beehive_scan
	id = "beehive_scan"
	name = "Scan"
	held_type = /obj/item/analyzer/plant_analyzer
	effect = /obj/machinery/beehive/proc/interaction_beehive_scan

/obj/machinery/beehive/proc/interaction_beehive_scan(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("Scan result of \the [src]..."))
	to_chat(user, "Beehive is [bee_count ? "[round(bee_count)]% full" : "empty"].[bee_count > 90 ? " Colony is ready to split." : ""]")
	if(length(frames))
		to_chat(user, "[length(frames)] frames installed, [round(honeycombs / 100)] filled.")
		if(honeycombs < length(frames) * 100)
			to_chat(user, "Next frame is [round(honeycombs % 100)]% full.")
	else
		to_chat(user, "No frames installed.")
	if(smoked)
		to_chat(user, "The hive is smoked.")
	return TRUE

/obj/machinery/beehive/crowbar_act(mob/user, obj/item/tool)
	closed = !closed
	act_message(user, src, MSG_SELF(span_notice("You [closed ? "close" : "open"] %T%.")), MSG_OTHERS(span_notice("%U% [closed ? "closes" : "opens"] %T%.")))
	changed(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/beehive/wrench_act(mob/user, obj/item/tool)
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF(span_notice("You [anchored ? "wrench" : "unwrench"] %T%.")), \
		MSG_OTHERS(span_notice("%U% [anchored ? "wrenches" : "unwrenches"] %T%.")))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/beehive/screwdriver_act(mob/user, obj/item/tool)
	if(bee_count)
		to_chat(user, span_notice("You can't dismantle \the [src] with these bees inside."))
		return ITEM_INTERACT_BLOCKING
	if(length(frames))
		to_chat(user, span_notice("You can't dismantle \the [src] with [length(frames)] frames still inside!"))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You start dismantling \the [src]..."))
	playsound(src, tool.usesound, 50, TRUE)
	om_task_timed(user, 3 SECONDS, src, src, PROC_REF(dismantle_done), list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/beehive/proc/dismantle_done(mob/user)
	if(bee_count || length(frames))
		return
	act_message(user, src, MSG_SELF(span_notice("You dismantle %T%.")), MSG_OTHERS(span_notice("%U% dismantles %T%.")))
	replace_with(src, /obj/item/beehive_assembly)

/datum/interaction/machine_hand/ungated/beehive_harvest
	id = "beehive_harvest"
	name = "Harvest honeycombs"
	effect = /obj/machinery/beehive/proc/interaction_beehive_harvest

/// One frame every 3 seconds (a timed action each) while there are filled honeycombs.
/obj/machinery/beehive/proc/harvest_next(mob/user)
	if(honeycombs >= 100 && length(frames))
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(harvest_frame), list(user))
	else if(honeycombs < 100)
		to_chat(user, span_notice("You take all filled honeycombs out."))

/obj/machinery/beehive/proc/harvest_frame(mob/user)
	if(honeycombs < 100 || !length(frames))
		return
	var/obj/item/honey_frame/H = pop(frames)
	H.honey = 20
	set_honeycombs(honeycombs - (100))
	H.forceMove(get_turf(src))
	changed(src)
	harvest_next(user)

/obj/machinery/beehive/proc/interaction_beehive_harvest(mob/user, obj/item/held, datum/interaction/interaction)
	if(!closed)
		if(honeycombs < 100)
			to_chat(user, span_notice("There are no filled honeycombs."))
			return TRUE
		if(!smoked && bee_count)
			to_chat(user, span_notice("The bees won't let you take the honeycombs out like this, smoke them first."))
			return TRUE
		act_message(user, src, MSG_SELF(span_notice("You start taking the honeycombs out of %T%...")), \
			MSG_OTHERS(span_notice("%U% starts taking the honeycombs out of %T%.")))
		harvest_next(user)
		return TRUE

/obj/machinery/beehive/proc/work_step(datum/act/timer/A)
	if(closed && !smoked && bee_count)
		pollinate_flowers()
	set_smoked(max(0, smoked - 1))
	if(!smoked && bee_count)
		set_bee_count(min(bee_count * 1.005, 100))

/obj/machinery/beehive/proc/pollinate_flowers()
	var/coef = bee_count / 100
	var/trays = 0
	for(var/obj/machinery/portable_atmospherics/hydroponics/H in view(7, src))
		if(H.seed && !H.dead)
			H.health += 0.05 * coef
			++trays
	set_honeycombs(min(honeycombs + 0.1 * coef * min(trays, 5), length(frames) * 100))

/obj/machinery/honey_extractor
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "honey extractor"
	desc = "A machine used to turn honeycombs on the frame into honey and wax."
	icon = 'icons/obj/beekeeping.dmi'
	icon_state = "centrifuge"
	circuit = /obj/item/circuitboard/honey_extractor
	anchored = TRUE
	density = TRUE
	idle_power_usage = 15
	active_power_usage = 200
	use_power = USE_POWER_IDLE

	var/processing = 0
	var/honey = 0

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and redraws for them
/obj/machinery/honey_extractor/Initialize(mapload)
	. = ..()
	default_apply_parts()
	RefreshParts()

/obj/machinery/honey_extractor/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		. += "It has [honey] units of honey in its storage tank."

/obj/machinery/honey_extractor/proc/appearance_state()
	if(has_stat(NOPOWER))
		return "[initial(icon_state)]_off"
	if(processing)
		return "[initial(icon_state)]_moving"
	return initial(icon_state)

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/honey_extractor/draw(datum/look/look)
	..()
	look.state("[appearance_state()]")
	if(panel_open == 1)
		look.overlay("centrifuge_panel")

/obj/machinery/honey_extractor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/honey_extractor_load_frame,
		/datum/interaction/machine_item/honey_extractor_collect,
	)
	..()

/// The old attackby's shared guard: not spinning, powered, panel closed.
/obj/machinery/honey_extractor/proc/ready_for_item(mob/actor, atom/target, obj/item/held)
	if(processing)
		return "it's currently spinning, wait until it's finished"
	if(has_stat(NOPOWER))
		return "it's powerless and can't grant your wishes"
	if(panel_open)
		return "its maintenance panel is open, it would not be safe to turn it on"
	return TRUE

/datum/interaction/machine_item/honey_extractor_load_frame
	id = "honey_extractor_load_frame"
	name = "Load frame"
	held_type = /obj/item/honey_frame
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/honey_extractor/proc/ready_for_item, null), REQ_TARGET_STATE(/obj/machinery/honey_extractor/proc/can_extract_frame))
	effect = /obj/machinery/honey_extractor/proc/interaction_honey_extractor_load_frame

/// Requirement: the frame has honey to extract.
/obj/machinery/honey_extractor/proc/can_extract_frame(mob/user, atom/target, obj/item/honey_frame/held)
	if(!held.honey)
		return "\The [held] is empty, put it into a beehive"
	return TRUE

/obj/machinery/honey_extractor/proc/interaction_honey_extractor_load_frame(mob/user, obj/item/honey_frame/held, datum/interaction/interaction)
	act_message(user, src, MSG_SELF(span_notice("You load %I% into %T% and turn it on.")), \
		MSG_OTHERS(span_notice("%U% loads %I%'s comb into %T% and turns it on.")), \
		item = held)
	processing = held.honey
	changed(src)
	use_power_oneoff(active_power_usage * 5) //uses 5 second of active power at once, because I could not figure out how active powerdraw works and if or how the work is timed.
	held.honey = 0
	after(src, 5 SECONDS, PROC_REF(finish_extracting))
	return TRUE

/datum/interaction/machine_item/honey_extractor_collect
	id = "honey_extractor_collect"
	name = "Collect honey"
	held_type = /obj/item/reagent_containers/glass
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/honey_extractor/proc/ready_for_item, null), REQ_FIELD("honey", "there is no honey in it"))
	effect = /obj/machinery/honey_extractor/proc/interaction_honey_extractor_collect

/obj/machinery/honey_extractor/proc/interaction_honey_extractor_collect(mob/user, obj/item/reagent_containers/glass/held, datum/interaction/interaction)
	var/transferred = min(held.reagents.maximum_volume - held.reagents.total_volume, honey)
	held.reagents.add_reagent(REAGENT_ID_HONEY, transferred)
	honey -= transferred
	act_message(user, src, MSG_SELF(span_notice("You collect [transferred] units of honey from %T% into %I%.")), \
		MSG_OTHERS(span_notice("%U% collects honey from %T% into %I%.")), \
		item = held)
	return TRUE

/obj/item/bee_smoker
	name = "bee smoker"
	desc = "A device used to calm down bees before harvesting honey."
	icon = 'icons/obj/device.dmi'
	icon_state = "battererburnt"
	w_class = ITEMSIZE_SMALL

/obj/item/honey_frame
	name = "beehive frame"
	desc = "A frame for the beehive that the bees will fill with honeycombs."
	icon = 'icons/obj/beekeeping.dmi'
	icon_state = "honeyframe"
	w_class = ITEMSIZE_SMALL

	var/honey = 0

/obj/item/honey_frame/proc/appearance_has_honey()
	return honey > 0

/// The look (the draw sweep: from its layers).
/obj/item/honey_frame/draw(datum/look/look)
	..()
	if(appearance_has_honey() == 1)
		look.overlay("honeycomb")

/obj/item/honey_frame/filled
	name = "filled beehive frame"
	desc = "A frame for the beehive that the bees have filled with honeycombs."
	honey = 20

/obj/item/beehive_assembly
	name = "beehive assembly"
	desc = "Contains everything you need to build a beehive."
	icon = 'icons/obj/apiary_bees_etc.dmi'
	icon_state = "apiary"

CAPABILITIES(/obj/item/beehive_assembly)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/beehive_assembly/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You start assembling \the [src]..."))
	om_task_timed(user, 3 SECONDS, src, src, PROC_REF(assemble_done), list(user))
	return TRUE

/obj/item/beehive_assembly/proc/assemble_done(mob/user)
	if(!consume(src, user))
		return
	act_message(user, null, MSG_SELF(span_notice("You construct a beehive.")), MSG_OTHERS(span_notice("%U% constructs a beehive.")))
	new /obj/machinery/beehive(get_turf(user))

/obj/item/stack/material/wax
	name = "wax"
	singular_name = "wax piece"
	desc = "Soft substance produced by bees. Used to make candles."
	icon = 'icons/obj/beekeeping.dmi'
	icon_state = "wax"
	default_type = MAT_WAX
	pass_color = TRUE
	strict_color_stacking = TRUE

/obj/item/stack/material/wax/Initialize(mapload)
	. = ..()
	recipes = GLOB.wax_recipes

/datum/material/wax
	name = MAT_WAX
	stack_type = /obj/item/stack/material/wax
	icon_colour = "#fff343"
	melting_point = T0C+300
	density = 1 // weight renamed to density.
	pass_stack_colors = TRUE
	supply_conversion_value = 0.5



/obj/item/bee_pack
	name = "bee pack"
	desc = "Contains a queen bee and some worker bees. Everything you'll need to start a hive!"
	icon = 'icons/obj/beekeeping.dmi'
	icon_state = "beepack"
	var/full = 1
TRACKED(/obj/item/bee_pack, full)

/// The look (the draw sweep: from its layers).
/obj/item/bee_pack/draw(datum/look/look)
	..()
	switch("[full]")
		if("0")
			look.overlay("beepack-empty")
		if("1")
			look.overlay("beepack-full")

/obj/item/bee_pack/proc/empty()
	set_full(0)
	name = "empty bee pack"
	desc = "A stasis pack for moving bees. It's empty."

/obj/item/bee_pack/proc/fill()
	set_full(initial(full))
	name = initial(name)
	desc = initial(desc)

/obj/machinery/honey_extractor/wrench_act(mob/user, obj/item/tool)
	if(processing)
		to_chat(user, span_notice("\The [src] is currently spinning, wait until it's finished."))
		return ITEM_INTERACT_BLOCKING
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF(span_notice("You [anchored ? "wrench" : "unwrench"] %T%.")), \
		MSG_OTHERS(span_notice("%U% [anchored ? "wrenches" : "unwrenches"] %T%.")))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/honey_extractor/screwdriver_act(mob/user, obj/item/tool)
	if(processing)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/honey_extractor/crowbar_act(mob/user, obj/item/tool)
	if(processing)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/honey_extractor/proc/finish_extracting()
	new /obj/item/stack/material/wax(loc)
	honey += processing
	processing = 0
	changed(src)
