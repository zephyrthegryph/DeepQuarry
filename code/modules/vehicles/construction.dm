/**
 * Vehicle assembly construction ladders (doc/rewrite/final_api.html section 12).
 *
 * Each `/obj/item/vehicle_assembly` builds up through a sequence of item, stack and tool stages. The last stage (a wrench or a screwdriver)
 * turns the assembly into the finished vehicle and moves the installed cell across. The assemblies are forward-only: no stage has a way back.
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

	var/tmp/obj/item/cell/cell

CAPABILITIES(/obj/item/vehicle_assembly)
	after_init(0, then(PROC_REF(frame_picture)))

/// Every assembly starts as its bare frame (stage 0 of its pictures).
/obj/item/vehicle_assembly/proc/frame_picture(datum/act/timer/A)
	set_build_visuals(0)

/// Sets the numbered icon_state for `stage` and, when given, the display name.
/obj/item/vehicle_assembly/proc/set_build_visuals(stage, new_name)
	if(new_name)
		name = new_name
	if(isnum(stage))
		icon_state = "[initial(icon_state)][stage]"

/// A stage was built: its picture and name, and what the actor is told.
/obj/item/vehicle_assembly/proc/step_done(datum/act/op/A, stage, new_name, message)
	set_build_visuals(stage, new_name)
	if(message)
		to_chat(A.actor, span_notice(message))
	return OP_OK

MSG_DEF_SELF(vehicle/start_tires, "You start to add tires to %T%.")
MSG_DEF_SELF(vehicle/start_treads, "You start to add treads to %T%.")
MSG_DEF_SELF(vehicle/start_seat, "You start to add a seat to %T%.")
MSG_DEF_SELF(vehicle/start_wire, "You start to wire %T%.")
MSG_DEF_SELF(vehicle/start_reinforce, "You start to add reinforcement to %T%.")
MSG_DEF_SELF(vehicle/start_finish, "You begin your finishing touches on %T%.")
MSG_DEF_SELF(quadtrailer/too_advanced, "%I% is too advanced to be of use with %T%.")

/*
 * Quadbike and trailer.
 */

STAGE_DEF(quadbike, frame)
STAGE_DEF(quadbike, wheeled)
STAGE_DEF(quadbike, lit)
STAGE_DEF(quadbike, controlled)
STAGE_DEF(quadbike, wired)
STAGE_DEF(quadbike, powered)
STAGE_DEF(quadbike, motored)
STAGE_DEF(quadbike, reinforced)
STAGE_DEF(quadbike, finished)
STAGE_DEF(quadbike, trailered)

MSG_DEF_SELF(stage/quadbike/frame, "It is a bare ATV frame.")
MSG_DEF_SELF(stage/quadbike/wheeled, "It has its tires.")
MSG_DEF_SELF(stage/quadbike/lit, "It has its lights.")
MSG_DEF_SELF(stage/quadbike/controlled, "It has its control system.")
MSG_DEF_SELF(stage/quadbike/wired, "It is wired.")
MSG_DEF_SELF(stage/quadbike/powered, "It has its power supply.")
MSG_DEF_SELF(stage/quadbike/motored, "It has its motor.")
MSG_DEF_SELF(stage/quadbike/reinforced, "It is reinforced.")
MSG_DEF_SELF(stage/quadbike/finished, "It is finished.")
MSG_DEF_SELF(stage/quadbike/trailered, "It has been made into a trailer.")

/obj/item/vehicle_assembly/quadbike
	name = "all terrain vehicle assembly"
	desc = "The frame of an ATV."
	icon_state = "quad-frame"
	pixel_x = -16

CAPABILITIES(/obj/item/vehicle_assembly/quadbike)
	construction(start(STAGE_QUADBIKE_FRAME),
		stage(STAGE_QUADBIKE_WHEELED, stack(/obj/item/stack/material/plastic, 8), wait(4 SECONDS), begins(MSG(vehicle/start_tires)), then(PROC_REF(tires_added)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_LIT, item(/obj/item/stock_parts/console_screen), consumes(), wait(0), then(PROC_REF(lights_added)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_CONTROLLED, item(/obj/item/stock_parts/spring), consumes(), wait(0), then(PROC_REF(controls_added)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_WIRED, stack(/obj/item/stack/cable_coil, 2), wait(4 SECONDS), begins(MSG(vehicle/start_wire)), then(PROC_REF(wired_up)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_POWERED, item(/obj/item/cell), wait(0), then(PROC_REF(power_added)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_MOTORED, item(/obj/item/stock_parts/motor), consumes(), wait(0), then(PROC_REF(motor_added)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_REINFORCED, stack(/obj/item/stack/material/plasteel, 2), wait(4 SECONDS), begins(MSG(vehicle/start_reinforce)), then(PROC_REF(reinforced)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_FINISHED, tool(TOOL_WRENCH), wait(2 SECONDS), begins(MSG(vehicle/start_finish)), then(PROC_REF(finished)), undo = NO_UNDO),
		stage(STAGE_QUADBIKE_FINISHED, tool(TOOL_SCREWDRIVER), wait(2 SECONDS), begins(MSG(vehicle/start_finish)), then(PROC_REF(finished)), from = STAGE_QUADBIKE_REINFORCED, key = "screwdriver", undo = NO_UNDO),
		stage(STAGE_QUADBIKE_TRAILERED, stack(/obj/item/stack/material/steel, 5), wait(8 SECONDS), then(PROC_REF(to_trailer)), from = STAGE_QUADBIKE_LIT, undo = NO_UNDO))

/obj/item/vehicle_assembly/quadbike/proc/tires_added(datum/act/op/A)
	return step_done(A, 1, "wheeled [initial(name)]", "You add tires to \the [src].")

/obj/item/vehicle_assembly/quadbike/proc/lights_added(datum/act/op/A)
	return step_done(A, 2, null, "You add the lights to \the [src].")

/obj/item/vehicle_assembly/quadbike/proc/controls_added(datum/act/op/A)
	return step_done(A, 3, null, "You add the control system to \the [src].")

/// Five sheets of steel turn a quadbike with its lights on straight into a framed trailer.
/obj/item/vehicle_assembly/quadbike/proc/to_trailer(datum/act/op/A)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = new(src)
	trailer.forceMove(get_turf(src))
	graph_place(trailer, STAGE_QUADTRAILER_FRAMED)
	trailer.set_build_visuals(1, "framed [initial(trailer.name)]")
	to_chat(A.actor, span_notice("You convert \the [src] into \the [trailer]."))
	consume(src, A.actor)
	return OP_OK

/obj/item/vehicle_assembly/quadbike/proc/wired_up(datum/act/op/A)
	return step_done(A, 4, "wired [initial(name)]", "You wire \the [src].")

/obj/item/vehicle_assembly/quadbike/proc/power_added(datum/act/op/A)
	var/obj/item/cell/power = A.held
	A.actor.drop_from_inventory(power)
	power.forceMove(src)
	rel_set(src, nameof(cell), power)
	return step_done(A, 5, "powered [initial(name)]", "You add the power supply to \the [src].")

/obj/item/vehicle_assembly/quadbike/proc/motor_added(datum/act/op/A)
	return step_done(A, 6, null, "You add the motor to \the [src].")

/obj/item/vehicle_assembly/quadbike/proc/reinforced(datum/act/op/A)
	return step_done(A, 7, "reinforced [initial(name)]", "You add reinforcement to \the [src].")

/obj/item/vehicle_assembly/quadbike/proc/finished(datum/act/op/A)
	playsound(src, A.held.usesound, 30, TRUE)
	var/obj/vehicle/train/engine/quadbike/built/product = new(src)
	to_chat(A.actor, span_notice("You finish \the [product]"))
	product.forceMove(get_turf(src))
	var/obj/item/cell/moved_cell = cell()
	rel_clear(src, nameof(cell))
	move_into(product, nameof(product.cell), moved_cell)
	consume(src, A.actor)
	return OP_OK

STAGE_DEF(quadtrailer, frame)
STAGE_DEF(quadtrailer, framed)
STAGE_DEF(quadtrailer, wired)
STAGE_DEF(quadtrailer, finished)

MSG_DEF_SELF(stage/quadtrailer/frame, "It is a bare trailer.")
MSG_DEF_SELF(stage/quadtrailer/framed, "It is framed.")
MSG_DEF_SELF(stage/quadtrailer/wired, "It is wired.")
MSG_DEF_SELF(stage/quadtrailer/finished, "It is finished.")

/obj/item/vehicle_assembly/quadtrailer
	name = "all terrain trailer"
	desc = "The frame of a small trailer."
	icon_state = "quadtrailer-frame"
	pixel_x = -16

CAPABILITIES(/obj/item/vehicle_assembly/quadtrailer)
	construction(start(STAGE_QUADTRAILER_FRAME),
		stage(STAGE_QUADTRAILER_FRAMED, item(/obj/item/vehicle_assembly/quadbike), consumes(), wait(0), needs(req(PROC_REF(spare_frame_fits), because = MSG(quadtrailer/too_advanced))), then(PROC_REF(framed)), undo = NO_UNDO),
		stage(STAGE_QUADTRAILER_WIRED, stack(/obj/item/stack/cable_coil, 2), wait(4 SECONDS), begins(MSG(vehicle/start_wire)), then(PROC_REF(wired_up)), undo = NO_UNDO),
		stage(STAGE_QUADTRAILER_FINISHED, tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(finished)), undo = NO_UNDO))

/// A spare quadbike frame helps only until its control system is in.
/obj/item/vehicle_assembly/quadtrailer/proc/spare_frame_fits(datum/act/op/A)
	return !built(A.held, STAGE_QUADBIKE_CONTROLLED) ? null : MSG(quadtrailer/too_advanced)

/obj/item/vehicle_assembly/quadtrailer/proc/framed(datum/act/op/A)
	return step_done(A, 1, "framed [initial(name)]", null)

/obj/item/vehicle_assembly/quadtrailer/proc/wired_up(datum/act/op/A)
	return step_done(A, 2, "wired [initial(name)]", "You wire \the [src].")

/obj/item/vehicle_assembly/quadtrailer/proc/finished(datum/act/op/A)
	to_chat(A.actor, span_notice("You close up \the [src]."))
	var/obj/vehicle/train/trolley/trailer/product = new(src)
	product.forceMove(get_turf(src))
	consume(src, A.actor)
	return OP_OK

/*
 * Space bike.
 */

STAGE_DEF(spacebike, frame)
STAGE_DEF(spacebike, jetpacked)
STAGE_DEF(spacebike, wired)
STAGE_DEF(spacebike, seated)
STAGE_DEF(spacebike, lit)
STAGE_DEF(spacebike, controlled)
STAGE_DEF(spacebike, powered)
STAGE_DEF(spacebike, finished)

MSG_DEF_SELF(stage/spacebike/frame, "It is a bare bike frame.")
MSG_DEF_SELF(stage/spacebike/jetpacked, "It has its jetpack.")
MSG_DEF_SELF(stage/spacebike/wired, "It is wired.")
MSG_DEF_SELF(stage/spacebike/seated, "It has its seat.")
MSG_DEF_SELF(stage/spacebike/lit, "It has its lights.")
MSG_DEF_SELF(stage/spacebike/controlled, "It has its control system.")
MSG_DEF_SELF(stage/spacebike/powered, "It has its power supply.")
MSG_DEF_SELF(stage/spacebike/finished, "It is finished.")

/obj/item/vehicle_assembly/spacebike
	name = "vehicle assembly"
	desc = "The frame of some vehicle."
	icon = 'icons/obj/bike.dmi'
	icon_state = "bike-frame"

	pixel_x = 0

CAPABILITIES(/obj/item/vehicle_assembly/spacebike)
	construction(start(STAGE_SPACEBIKE_FRAME),
		stage(STAGE_SPACEBIKE_JETPACKED, inputs(item(/obj/item/tank/jetpack), item(/obj/item/borg/upgrade/advanced/jetpack)), consumes(), wait(0), then(PROC_REF(jetpack_added)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_WIRED, stack(/obj/item/stack/cable_coil, 2), wait(4 SECONDS), begins(MSG(vehicle/start_wire)), then(PROC_REF(wired_up)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_SEATED, stack(/obj/item/stack/material/plastic, 3), wait(4 SECONDS), begins(MSG(vehicle/start_seat)), then(PROC_REF(seat_added)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_LIT, item(/obj/item/stock_parts/console_screen), consumes(), wait(0), then(PROC_REF(lights_added)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_CONTROLLED, item(/obj/item/stock_parts/spring), consumes(), wait(0), then(PROC_REF(controls_added)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_POWERED, item(/obj/item/cell), wait(0), then(PROC_REF(power_added)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_FINISHED, tool(TOOL_WRENCH), wait(2 SECONDS), begins(MSG(vehicle/start_finish)), then(PROC_REF(finished)), undo = NO_UNDO),
		stage(STAGE_SPACEBIKE_FINISHED, tool(TOOL_SCREWDRIVER), wait(2 SECONDS), begins(MSG(vehicle/start_finish)), then(PROC_REF(finished)), from = STAGE_SPACEBIKE_POWERED, key = "screwdriver", undo = NO_UNDO))

/obj/item/vehicle_assembly/spacebike/proc/jetpack_added(datum/act/op/A)
	return step_done(A, 1, null, null)

/obj/item/vehicle_assembly/spacebike/proc/wired_up(datum/act/op/A)
	return step_done(A, 2, "wired [initial(name)]", "You wire \the [src].")

/obj/item/vehicle_assembly/spacebike/proc/seat_added(datum/act/op/A)
	return step_done(A, 3, "seated [initial(name)]", "You add a seat to \the [src].")

/obj/item/vehicle_assembly/spacebike/proc/lights_added(datum/act/op/A)
	return step_done(A, 4, null, "You add the lights to \the [src].")

/obj/item/vehicle_assembly/spacebike/proc/controls_added(datum/act/op/A)
	return step_done(A, 5, null, "You add the control system to \the [src].")

/obj/item/vehicle_assembly/spacebike/proc/power_added(datum/act/op/A)
	var/obj/item/cell/power = A.held
	A.actor.drop_from_inventory(power)
	power.forceMove(src)
	rel_set(src, nameof(cell), power)
	return step_done(A, 6, "powered [initial(name)]", "You add the power supply to \the [src].")

/obj/item/vehicle_assembly/spacebike/proc/finished(datum/act/op/A)
	playsound(src, A.held.usesound, 30, TRUE)
	var/obj/vehicle/bike/built/product = new(src)
	to_chat(A.actor, span_notice("You finish \the [product]"))
	product.forceMove(get_turf(src))
	var/obj/item/cell/moved_cell = cell()
	rel_clear(src, nameof(cell))
	move_into(product, nameof(product.cell), moved_cell)
	consume(src, A.actor)
	return OP_OK

/*
 * Snowmobile.
 */

STAGE_DEF(snowmobile, frame)
STAGE_DEF(snowmobile, tracked)
STAGE_DEF(snowmobile, lit)
STAGE_DEF(snowmobile, controlled)
STAGE_DEF(snowmobile, wired)
STAGE_DEF(snowmobile, powered)
STAGE_DEF(snowmobile, motored)
STAGE_DEF(snowmobile, reinforced)
STAGE_DEF(snowmobile, finished)

MSG_DEF_SELF(stage/snowmobile/frame, "It is a bare snowmobile frame.")
MSG_DEF_SELF(stage/snowmobile/tracked, "It has its treads.")
MSG_DEF_SELF(stage/snowmobile/lit, "It has its lights.")
MSG_DEF_SELF(stage/snowmobile/controlled, "It has its control system.")
MSG_DEF_SELF(stage/snowmobile/wired, "It is wired.")
MSG_DEF_SELF(stage/snowmobile/powered, "It has its power supply.")
MSG_DEF_SELF(stage/snowmobile/motored, "It has its motor.")
MSG_DEF_SELF(stage/snowmobile/reinforced, "It is reinforced.")
MSG_DEF_SELF(stage/snowmobile/finished, "It is finished.")

/obj/item/vehicle_assembly/snowmobile
	name = "snowmobile assembly"
	desc = "The frame of a snowmobile."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "snowmobile-frame"

CAPABILITIES(/obj/item/vehicle_assembly/snowmobile)
	construction(start(STAGE_SNOWMOBILE_FRAME),
		stage(STAGE_SNOWMOBILE_TRACKED, stack(/obj/item/stack/material/steel, 6), wait(4 SECONDS), begins(MSG(vehicle/start_treads)), then(PROC_REF(treads_added)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_LIT, item(/obj/item/stock_parts/console_screen), consumes(), wait(0), then(PROC_REF(lights_added)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_CONTROLLED, item(/obj/item/stock_parts/spring), consumes(), wait(0), then(PROC_REF(controls_added)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_WIRED, stack(/obj/item/stack/cable_coil, 2), wait(4 SECONDS), begins(MSG(vehicle/start_wire)), then(PROC_REF(wired_up)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_POWERED, item(/obj/item/cell), wait(0), then(PROC_REF(power_added)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_MOTORED, item(/obj/item/stock_parts/motor), consumes(), wait(0), then(PROC_REF(motor_added)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_REINFORCED, stack(/obj/item/stack/material/plasteel, 2), wait(4 SECONDS), begins(MSG(vehicle/start_reinforce)), then(PROC_REF(reinforced)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_FINISHED, tool(TOOL_WRENCH), wait(2 SECONDS), begins(MSG(vehicle/start_finish)), then(PROC_REF(finished)), undo = NO_UNDO),
		stage(STAGE_SNOWMOBILE_FINISHED, tool(TOOL_SCREWDRIVER), wait(2 SECONDS), begins(MSG(vehicle/start_finish)), then(PROC_REF(finished)), from = STAGE_SNOWMOBILE_REINFORCED, key = "screwdriver", undo = NO_UNDO))

/obj/item/vehicle_assembly/snowmobile/proc/treads_added(datum/act/op/A)
	return step_done(A, 1, "tracked [initial(name)]", "You add treads to \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/lights_added(datum/act/op/A)
	return step_done(A, 2, null, "You add the lights to \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/controls_added(datum/act/op/A)
	return step_done(A, 3, null, "You add the control system to \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/wired_up(datum/act/op/A)
	return step_done(A, 4, "wired [initial(name)]", "You wire \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/power_added(datum/act/op/A)
	var/obj/item/cell/power = A.held
	A.actor.drop_from_inventory(power)
	power.forceMove(src)
	rel_set(src, nameof(cell), power)
	return step_done(A, 5, "powered [initial(name)]", "You add the power supply to \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/motor_added(datum/act/op/A)
	return step_done(A, 6, null, "You add the motor to \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/reinforced(datum/act/op/A)
	return step_done(A, 7, "reinforced [initial(name)]", "You add reinforcement to \the [src].")

/obj/item/vehicle_assembly/snowmobile/proc/finished(datum/act/op/A)
	playsound(src, A.held.usesound, 30, TRUE)
	var/obj/vehicle/train/engine/quadbike/snowmobile/built/product = new(src)
	to_chat(A.actor, span_notice("You finish \the [product]"))
	product.forceMove(get_turf(src))
	var/obj/item/cell/moved_cell = cell()
	rel_clear(src, nameof(cell))
	move_into(product, nameof(product.cell), moved_cell)
	consume(src, A.actor)
	return OP_OK

/// Accessor for the cell var.
/obj/item/vehicle_assembly/proc/cell() as /obj/item/cell
	return cell
