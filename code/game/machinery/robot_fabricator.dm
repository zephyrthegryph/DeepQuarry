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

/// No side effects: whether this stack is steel and we're not already mid-insertion.
/obj/machinery/robotic_fabricator/proc/wants_steel(mob/actor, atom/target, obj/item/stack/material/held)
	if(inserting)
		return FALSE
	return istype(held) && held.get_material_name() == MAT_STEEL

/// Requirement (was REQ_* wants_steel): the legacy check answers TRUE to pass.
/obj/machinery/robotic_fabricator/proc/wants_steel_holds(datum/act/op/A)
	var/answer = wants_steel(A.actor, src, A.held)
	return !istext(answer) && !!answer

/obj/machinery/robotic_fabricator/proc/interaction_insert_steel(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/supplied_stack = A.held
	if(metal_amount < 150000)
		if(!supplied_stack.get_amount())
			return TRUE
		add_overlay("fab-load-metal")
		set_inserting(TRUE)
		after(src, 0.9 SECONDS, PROC_REF(complete_insertion), with = list(user, supplied_stack))
		return TRUE
	to_chat(user, "The robot part maker is full. Please remove metal from the robot part maker in order to insert more.")
	return TRUE

/obj/machinery/robotic_fabricator/proc/interaction_reject(datum/act/op/A)
	return TRUE

/obj/machinery/robotic_fabricator/proc/complete_insertion(mob/user, obj/item/stack/supplied_stack)
	var/count = 0
	while(metal_amount < 150000 && !QDELETED(supplied_stack) && supplied_stack.get_amount() > 0)
		var/steel_amount = supplied_stack.material_totals()[MAT_STEEL]
		if(!supplied_stack.use(1))
			break
		set_metal_amount(metal_amount + steel_amount)
		count++

	to_chat(user, "You insert [count] metal sheet\s into the fabricator.")
	cut_overlay("fab-load-metal")
	set_inserting(FALSE)

TRACKED(/obj/machinery/robotic_fabricator, metal_amount)
TRACKED(/obj/machinery/robotic_fabricator, operating)
TRACKED(/obj/machinery/robotic_fabricator, inserting)

MSG_DEF_SELF(robot_fabricator/busy, "The fabricator is already building a part.")
MSG_DEF_SELF(robot_fabricator/metal, "The fabricator does not have enough metal.")

CAPABILITIES(/obj/machinery/robotic_fabricator)
	contributes(STAT_OPERABLE, TYPE_PROC_REF(/obj/machinery, stat_bits_allow), reads = list("stat"))
	interface("AncientDroneFab")
	extend("ui_open", needs(req_operable()))
	op("build_l_arm", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 25000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_l_arm)))
	op("build_r_arm", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 25000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_r_arm)))
	op("build_l_leg", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 25000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_l_leg)))
	op("build_r_leg", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 25000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_r_leg)))
	op("build_chest", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 50000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_chest)))
	op("build_head", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 50000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_head)))
	op("build_frame", ui_act(), needs(req_is(nameof(operating), FALSE, because = MSG(robot_fabricator/busy)), req_at_least(nameof(metal_amount), 75000, because = MSG(robot_fabricator/metal))), then(PROC_REF(build_frame)))
	op("insert_steel", item(/obj/item/stack/material), priority(OP_PRIORITY_DEFAULT - 1), label("Insert metal"), when(req(PROC_REF(wants_steel_holds))), then(PROC_REF(interaction_insert_steel)))
	op("reject", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_reject)))

/obj/machinery/robotic_fabricator/ui_data(datum/act/eval/A)
	return list("operating" = operating, "metal_amount" = metal_amount)

/obj/machinery/robotic_fabricator/proc/build_l_arm(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/l_arm, 20 SECONDS, 25000)

/obj/machinery/robotic_fabricator/proc/build_r_arm(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/r_arm, 20 SECONDS, 25000)

/obj/machinery/robotic_fabricator/proc/build_l_leg(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/l_leg, 20 SECONDS, 25000)

/obj/machinery/robotic_fabricator/proc/build_r_leg(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/r_leg, 20 SECONDS, 25000)

/obj/machinery/robotic_fabricator/proc/build_chest(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/chest, 35 SECONDS, 50000)

/obj/machinery/robotic_fabricator/proc/build_head(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/head, 35 SECONDS, 50000)

/obj/machinery/robotic_fabricator/proc/build_frame(datum/act/op/A)
	add_fingerprint(A.actor)
	return try_start_building(/obj/item/robot_parts/robot_suit, 60 SECONDS, 75000)

/obj/machinery/robotic_fabricator/proc/try_start_building(build_type, build_time, build_cost)
	var/building = build_type
	if(isnull(building))
		return FALSE

	if(metal_amount < build_cost)
		return FALSE

	set_operating(TRUE)
	set_use_power(USE_POWER_ACTIVE)
	set_metal_amount(max(0, metal_amount - build_cost))
	add_overlay("fab-active")

	after(src, build_time, PROC_REF(complete_building), with = list(building))
	return TRUE

/obj/machinery/robotic_fabricator/proc/complete_building(building)
	rel_set(src, nameof(being_built), new building(src))
	being_built.forceMove(get_turf(src))
	rel_take(src, nameof(being_built))
	set_use_power(USE_POWER_IDLE)
	set_operating(FALSE)
	cut_overlay("fab-active")

/obj/machinery/robotic_fabricator/ownership()
	. = ..()
	. += owns(nameof(being_built), policy = OWN_CONTAINED)
