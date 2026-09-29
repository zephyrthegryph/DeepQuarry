/obj/machinery/robotic_fabricator
	name = "robotic fabricator"
	icon = 'icons/obj/robotics.dmi'
	icon_state = "fab-idle"
	density = TRUE
	anchored = TRUE
	var/metal_amount = 0
	var/operating = FALSE
	var/obj/item/robot_parts/being_built = null
	use_power = USE_POWER_IDLE
	idle_power_usage = 40
	active_power_usage = 10000
	var/inserting = FALSE

/obj/machinery/robotic_fabricator/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/fabricator_insert_steel,
		/datum/interaction/machine_item/fabricator_reject,
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/// Old attackby's only branch.
/datum/interaction/machine_item/fabricator_insert_steel
	id = "fabricator_insert_steel"
	name = "Insert metal"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/stack/material
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/robotic_fabricator/proc/wants_steel, null))
	effect = /obj/machinery/robotic_fabricator/proc/interaction_insert_steel

/// No side effects: whether this stack is steel and we're not already mid-insertion.
/obj/machinery/robotic_fabricator/proc/wants_steel(mob/actor, atom/target, obj/item/stack/material/held)
	if(inserting)
		return FALSE
	return istype(held) && held.get_material_name() == MAT_STEEL

/obj/machinery/robotic_fabricator/proc/interaction_insert_steel(mob/user, obj/item/stack/supplied_stack, datum/interaction/interaction)
	if(metal_amount < 150000)
		if(!supplied_stack.get_amount())
			return TRUE
		add_overlay("fab-load-metal")
		inserting = TRUE
		om_after(src, 0.9 SECONDS, PROC_REF(complete_insertion), user, supplied_stack)
		return TRUE
	to_chat(user, "The robot part maker is full. Please remove metal from the robot part maker in order to insert more.")
	return TRUE

/// Old attackby: fell off the end for anything else, silently doing nothing (no ..() call).
/datum/interaction/machine_item/fabricator_reject
	id = "fabricator_reject"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/robotic_fabricator/proc/interaction_reject

/obj/machinery/robotic_fabricator/proc/interaction_reject(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/machinery/robotic_fabricator/proc/complete_insertion(mob/user, obj/item/stack/supplied_stack)
	var/count = 0
	while(metal_amount < 150000 && supplied_stack.get_amount())
		metal_amount += supplied_stack.material_totals()[MAT_STEEL]
		supplied_stack.use(1)
		count++

	to_chat(user, "You insert [count] metal sheet\s into the fabricator.")
	cut_overlay("fab-load-metal")
	inserting = FALSE

DECLARE_UI(/obj/machinery/robotic_fabricator, "AncientDroneFab")

UI_DATA_REPLACE(/obj/machinery/robotic_fabricator, "merge:ui_data_obj_machinery_robotic_fabricator{operating:num,metal_amount:num}")

/// The computed part of /obj/machinery/robotic_fabricator's window data (declared on its UI_DATA row).
/obj/machinery/robotic_fabricator/proc/ui_data_obj_machinery_robotic_fabricator(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"operating" = operating,
		"metal_amount" = metal_amount
	)

/obj/machinery/robotic_fabricator/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(operating)
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/robotic_fabricator, "build_l_arm", ui_act_build_l_arm)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_l_arm)
	return try_start_building("/obj/item/robot_parts/l_arm", 20 SECONDS, 25000)

UI_ACT(/obj/machinery/robotic_fabricator, "build_r_arm", ui_act_build_r_arm)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_r_arm)
	return try_start_building("/obj/item/robot_parts/r_arm", 20 SECONDS, 25000)

UI_ACT(/obj/machinery/robotic_fabricator, "build_l_leg", ui_act_build_l_leg)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_l_leg)
	return try_start_building("/obj/item/robot_parts/l_leg", 20 SECONDS, 25000)

UI_ACT(/obj/machinery/robotic_fabricator, "build_r_leg", ui_act_build_r_leg)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_r_leg)
	return try_start_building("/obj/item/robot_parts/r_leg", 20 SECONDS, 25000)

UI_ACT(/obj/machinery/robotic_fabricator, "build_chest", ui_act_build_chest)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_chest)
	return try_start_building("/obj/item/robot_parts/chest", 35 SECONDS, 50000)

UI_ACT(/obj/machinery/robotic_fabricator, "build_head", ui_act_build_head)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_head)
	return try_start_building("/obj/item/robot_parts/head", 35 SECONDS, 50000)

UI_ACT(/obj/machinery/robotic_fabricator, "build_frame", ui_act_build_frame)
UI_ACT_PROC(/obj/machinery/robotic_fabricator, ui_act_build_frame)
	return try_start_building("/obj/item/robot_parts/robot_suit", 60 SECONDS, 75000)

/obj/machinery/robotic_fabricator/proc/try_start_building(build_type, build_time, build_cost)
	var/building = text2path(build_type)
	if(isnull(building))
		return FALSE

	if(metal_amount < build_cost)
		return FALSE

	operating = TRUE
	set_use_power(USE_POWER_ACTIVE)
	metal_amount = max(0, metal_amount - build_cost)
	add_overlay("fab-active")

	om_after(src, build_time, PROC_REF(complete_building), building)
	return TRUE

/obj/machinery/robotic_fabricator/proc/complete_building(building)
	own_set(src, nameof(being_built), new building(src))
	being_built.forceMove(get_turf(src))
	own_take(src, nameof(being_built))
	set_use_power(USE_POWER_IDLE)
	operating = FALSE
	cut_overlay("fab-active")

/obj/machinery/robotic_fabricator/ownership()
	. = ..()
	. += owns(nameof(being_built), policy = OWN_CONTAINED)
