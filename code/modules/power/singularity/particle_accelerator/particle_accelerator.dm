/*Composed of 7 parts
3 Particle emitters
proc
emit_particle()

1 power box
the only part of this thing that uses power, can hack to mess with the pa/make it better.
Lies, only the control computer draws power.

1 fuel chamber
contains procs for mixing gas and whatever other fuel it uses
mix_gas()

1 End Cap

1 Control computer
interface for the pa, acts like a computer with an html menu for diff parts and a status report
all other parts contain only a ref to this
a /machine/, tells the others to do work
contains ref for all parts

 * Setup map
 *   |EC|
 * CC|FC|
 *   |PB|
 * PE|PE|PE

Icon Addemdum
Each part has a reference string, powered, strength, and construction stage, so the icon_state comes out as
"[reference][strength]":
Standard - [reference]
Wrenched - [reference]
Wired    - [reference]w
Closed   - [reference]c
Powered  - [reference]p[strength]
Strength being set by the computer and a null strength (Computer is powered off or inactive) returns a 'null', counting as empty
*/

// Every part of the accelerator, the control box included, is built on one ladder (doc/rewrite/final_api.html section 12): loose, bolted down
// (a wrench), wired (a length of cable; wirecutters take it out), closed (a screwdriver; it opens the same way). pa_stage() reads it as the old
// 0..3 number. A part placed finished (the pre_mapped subtypes) starts closed.
STAGE_DEF(pa, loose)
STAGE_DEF(pa, bolted)
STAGE_DEF(pa, wired)
STAGE_DEF(pa, closed)

MSG_DEF_SELF(stage/pa/loose, "Looks like it's not attached to the flooring.")
MSG_DEF_SELF(stage/pa/bolted, "It is missing some cables.")
MSG_DEF_SELF(stage/pa/wired, "The panel is open.")
MSG_DEF_SELF(stage/pa/closed, "It is assembled.")

/// The 0..3 construction stage of a part of the accelerator (its build ladder's current stage).
/proc/pa_stage_of(datum/part)
	READS_FROM(part)
	if(built(part, STAGE_PA_CLOSED))
		return 3
	if(built(part, STAGE_PA_WIRED))
		return 2
	if(built(part, STAGE_PA_BOLTED))
		return 1
	return 0

/// What a stage of the ladder says about the part.
/proc/pa_stage_examine(datum/part)
	switch(pa_stage_of(part))
		if(0)
			return /datum/msg/stage/pa/loose
		if(1)
			return /datum/msg/stage/pa/bolted
		if(2)
			return /datum/msg/stage/pa/wired
	return /datum/msg/stage/pa/closed

/obj/structure/particle_accelerator
	name = "Particle Accelerator"
	desc = "Part of a Particle Accelerator."
	icon = 'icons/obj/machines/particle_accelerator2.dmi'
	icon_state = "none"
	anchored = FALSE
	density = TRUE
	/// The control box this part answers to (part_scan() links it).
	var/tmp/obj/machinery/particle_accelerator/control_box/master
	var/reference = null
	var/powered = 0
	var/strength = null
	var/desc_holder = null

CAPABILITIES(/obj/structure/particle_accelerator)
	climb()
	rotatable()
	ref_one(nameof(master), /obj/machinery/particle_accelerator/control_box)
	construction(start(STAGE_PA_LOOSE),
		stage(STAGE_PA_BOLTED, tool(TOOL_WRENCH), wait(0), then(PROC_REF(bolted)), undone(PROC_REF(unbolted)), undo = list(tool(TOOL_WRENCH), wait(0))),
		stage(STAGE_PA_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(0), then(PROC_REF(wired)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(0))),
		stage(STAGE_PA_CLOSED, tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(closed)), undone(PROC_REF(opened)), undo = list(tool(TOOL_SCREWDRIVER), wait(0))))
	examine_line(PROC_REF(examine_stage))

/// Its 0..3 construction stage.
/obj/structure/particle_accelerator/proc/pa_stage()
	return pa_stage_of(src)

/obj/structure/particle_accelerator/proc/examine_stage(datum/act/A)
	return pa_stage_examine(src)

// its control box rescans its parts.
/obj/structure/particle_accelerator/on_destroy(force)
	master?.part_scan()
	..()

/obj/structure/particle_accelerator/proc/bolted(datum/act/op/A)
	set_anchored(TRUE)
	act_message(A.actor, null, MSG_SELF("You secure the external bolts."), MSG_OTHERS("[A.actor.name] secures the [src.name] to the floor."))
	return stage_moved()

/obj/structure/particle_accelerator/proc/unbolted(datum/act/op/A)
	set_anchored(FALSE)
	act_message(A.actor, null, MSG_SELF("You remove the external bolts."), MSG_OTHERS("[A.actor.name] detaches the [src.name] from the floor."))
	return stage_moved()

/obj/structure/particle_accelerator/proc/wired(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You add some wires."), MSG_OTHERS("[A.actor.name] adds wires to the [src.name]."))
	return stage_moved()

/obj/structure/particle_accelerator/proc/unwired(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You remove some wires."), MSG_OTHERS("[A.actor.name] removes some wires from the [src.name]."))
	return stage_moved()

/obj/structure/particle_accelerator/proc/closed(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You close the access panel."), MSG_OTHERS("[A.actor.name] closes the [src.name]'s access panel."))
	return OP_OK

/obj/structure/particle_accelerator/proc/opened(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You open the access panel."), MSG_OTHERS("[A.actor.name] opens the [src.name]'s access panel."))
	return stage_moved()

/// The part came apart a step: its control box rescans.
/obj/structure/particle_accelerator/proc/stage_moved()
	update_state()
	return OP_OK

/obj/structure/particle_accelerator/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(master?.active)
		master.toggle_power()
		log_game("PACCEL([x],[y],[z]) Was moved while active and turned off.")
		investigate_log("was moved whilst active; it " + span_red("powered down") + ".","singulo")

/obj/structure/particle_accelerator/draw(datum/look/look)
	..()
	var/suffix = ""
	switch(pa_stage())
		if(2)
			suffix = "w"
		if(3)
			suffix = powered ? "p[strength]" : "c"
	look.state("[reference][suffix]")

/obj/structure/particle_accelerator/proc/update_state()
	master?.update_state()
	return 0

/obj/structure/particle_accelerator/proc/report_ready(obj/O)
	return O && O == master && !QDELETED(src) && pa_stage() >= 3

/obj/structure/particle_accelerator/proc/report_master()
	return master || 0

/obj/structure/particle_accelerator/proc/connect_master(obj/O)
	if(O && istype(O,/obj/machinery/particle_accelerator/control_box))
		if(O.dir == src.dir)
			rel_set(src, nameof(master), O)
			return 1
	return 0

/obj/structure/particle_accelerator/end_cap
	name = "Alpha Particle Generation Array"
	desc_holder = "This is where Alpha particles are generated from \[REDACTED\]"
	icon_state = "end_cap"
	reference = "end_cap"

/obj/structure/particle_accelerator/end_cap/pre_mapped
	anchored = TRUE

CAPABILITIES(/obj/structure/particle_accelerator/end_cap/pre_mapped)
	configure(construction_graph(start = STAGE_PA_CLOSED, via = list(STAGE_PA_BOLTED, STAGE_PA_WIRED)))

// ---- the control box's base ----

/obj/machinery/particle_accelerator
	name = "Particle Accelerator"
	desc = "Part of a Particle Accelerator."
	icon = 'icons/obj/machines/particle_accelerator2.dmi'
	icon_state = "none"
	anchored = FALSE
	density = TRUE
	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0
	active = 0
	var/reference = null
	var/powered = null
	var/strength = 0
	var/desc_holder = null

CAPABILITIES(/obj/machinery/particle_accelerator)
	climb()
	rotatable()
	construction(start(STAGE_PA_LOOSE),
		stage(STAGE_PA_BOLTED, tool(TOOL_WRENCH), wait(0), then(PROC_REF(bolted)), undone(PROC_REF(unbolted)), undo = list(tool(TOOL_WRENCH), wait(0))),
		stage(STAGE_PA_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(0), then(PROC_REF(wired)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(0))),
		stage(STAGE_PA_CLOSED, tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(closed)), undone(PROC_REF(opened)), undo = list(tool(TOOL_SCREWDRIVER), wait(0))))
	examine_line(PROC_REF(examine_stage))

/// Its 0..3 construction stage.
/obj/machinery/particle_accelerator/proc/pa_stage()
	return pa_stage_of(src)

/obj/machinery/particle_accelerator/proc/examine_stage(datum/act/A)
	return pa_stage_examine(src)

/obj/machinery/particle_accelerator/proc/bolted(datum/act/op/A)
	set_anchored(TRUE)
	act_message(A.actor, null, MSG_SELF("You secure the external bolts."), MSG_OTHERS("[A.actor.name] secures the [src.name] to the floor."))
	return OP_OK

/obj/machinery/particle_accelerator/proc/unbolted(datum/act/op/A)
	set_anchored(FALSE)
	act_message(A.actor, null, MSG_SELF("You remove the external bolts."), MSG_OTHERS("[A.actor.name] detaches the [src.name] from the floor."))
	return OP_OK

/obj/machinery/particle_accelerator/proc/wired(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You add some wires."), MSG_OTHERS("[A.actor.name] adds wires to the [src.name]."))
	return OP_OK

/obj/machinery/particle_accelerator/proc/unwired(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You remove some wires."), MSG_OTHERS("[A.actor.name] removes some wires from the [src.name]."))
	return OP_OK

/// Closed: it powers up idle.
/obj/machinery/particle_accelerator/proc/closed(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You close the access panel."), MSG_OTHERS("[A.actor.name] closes the [src.name]'s access panel."))
	set_use_power(USE_POWER_IDLE)
	update_state()
	return OP_OK

/// Opened: it stops and powers down.
/obj/machinery/particle_accelerator/proc/opened(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You open the access panel."), MSG_OTHERS("[A.actor.name] opens the [src.name]'s access panel."))
	set_active(0)
	set_use_power(USE_POWER_OFF)
	update_state()
	return OP_OK

/obj/machinery/particle_accelerator/proc/update_state()
	return 0
