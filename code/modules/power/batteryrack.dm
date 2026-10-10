// Cell rack PSU, similar to SMES, but uses power cells to store power.
// Lacks detailed control of input/output values, and has generally much worse capacity.
//
// The rack is a power storage unit that keeps its charge in power cells instead of in Rust's counter, so it is declared on top of the SMES
// (code/modules/power/smes.dm): the casing, the input terminals, the hatch and the part replacer are the SMES's; the rack takes away the SMES's
// own window buttons, says what it opens instead (its own window), and adds the cells: an owned list, an op that takes one from a hand, the
// window buttons that set its mode and eject a cell, and the frame that reads the cells back and balances them.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits (BROKEN, ...) read through machine_basics()'s one bridge
// contribution, `mode` (a machine core field, written with set_mode()), RefreshParts() with the circuit board and its parts, and maintenance_flags.

#define PSU_OFFLINE 0
#define PSU_OUTPUT 1
#define PSU_INPUT 2
#define PSU_AUTO 3

#define PSU_MAXCELLS 9 // Capped to 9 cells due to sprite limitation

MSG_DEF_SELF(batteryrack/inserted, "You insert %I% into %T%.")
MSG_DEF_SELF(batteryrack/full, "It has no empty slot for that.")

/obj/machinery/power/smes/batteryrack
	name = "power cell rack PSU"
	desc = "A rack of power cells working as a PSU. Made from a recycled Breaker Box frame."
	icon = 'icons/obj/cellrack.dmi'
	icon_state = "rack"
	capacity = 0
	initial_charge = 0
	output_attempt = FALSE
	input_attempt = FALSE

	/// Maximal input/output rate. Determined by used capacitors when building the device.
	var/max_transfer_rate = 0
	mode = PSU_OFFLINE // Current inputting/outputting mode
	/// Cells stored in this PSU (owned: they go when the rack does).
	var/list/internal_cells
	/// Maximal amount of stored cells at once. Capped at 9.
	var/max_cells = 3
	/// If true try to equalise charge between cells.
	var/equalise = FALSE
	/// Flips every frame: the window's blink.
	var/ui_tick = FALSE
	/// The overlays the rack shows (comma separated icon states), refreshed when its cells or its charge change.
	var/shown_overlays = ""
	circuit = /obj/item/circuitboard/batteryrack

TRACKED(/obj/machinery/power/smes/batteryrack, max_transfer_rate)
TRACKED(/obj/machinery/power/smes/batteryrack, max_cells)
TRACKED(/obj/machinery/power/smes/batteryrack, equalise)
TRACKED(/obj/machinery/power/smes/batteryrack, ui_tick)
TRACKED(/obj/machinery/power/smes/batteryrack, shown_overlays)

CAPABILITIES(/obj/machinery/power/smes/batteryrack)
	without("tryinput")
	without("tryoutput")
	without("input")
	without("output")
	without("ui_open")
	owns_many(nameof(internal_cells), /obj/item/cell)
	part_replacement()
	interface("Batteryrack")
	extend("ui_open", ungated()) // the window opens on an inoperable rack too; its buttons stay behind the operable gate
	op("insert_cell", item(/obj/item/cell), needs(req(PROC_REF(cell_room))), then(PROC_REF(cell_inserted)), says(MSG(batteryrack/inserted)))
	op("disable", ui_act(), then(PROC_REF(ui_disable)))
	op("enable", ui_act(arg("enable")), then(PROC_REF(ui_enable)))
	op("equaliseon", ui_act(), sets(nameof(equalise), TRUE))
	op("equaliseoff", ui_act(), sets(nameof(equalise), FALSE))
	op("ejectcell", ui_act(arg("ejectcell")), then(PROC_REF(ui_eject_cell)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(power_frame)))

/obj/machinery/power/smes/batteryrack/Initialize(mapload)
	. = ..()
	default_apply_parts()
	sync_look()

/obj/machinery/power/smes/batteryrack/RefreshParts()
	var/capacitor_efficiency = get_part_rating(/obj/item/stock_parts/capacitor)
	var/maxcells = get_part_rating(/obj/item/stock_parts/matter_bin) * 3

	set_max_transfer_rate(10000 * capacitor_efficiency) // 30kw - 90kw depending on used capacitors.
	set_max_cells(min(PSU_MAXCELLS, maxcells))
	set_input_level(max_transfer_rate)
	set_output_level(max_transfer_rate)


/// A rack keeps its charge in cells: it works without an input terminal.
/obj/machinery/power/smes/batteryrack/needs_terminals()
	return FALSE

// ---- what it shows ----

/// A cell rack draws its own cells and charge gauge (shown_overlays), not the SMES's status overlays.
/obj/machinery/power/smes/batteryrack/draw_status(datum/look/look)
	for(var/key in splittext(shown_overlays, ","))
		look.overlay(key)

/// The icon states of the rack now: the charge gauge, and a layer per cell (marked when it is full or empty).
/obj/machinery/power/smes/batteryrack/proc/rack_overlays()
	. = list()
	var/cellcount = 0
	var/charge_level = clamp(round(Percentage() / 12), 0, 7)

	. += "charge[charge_level]"

	for(var/obj/item/cell/C in internal_cells)
		cellcount++
		. += "cell[cellcount]"
		if(C.fully_charged())
			. += "cell[cellcount]f"
		else if(!C.charge)
			. += "cell[cellcount]e"

/// The look follows the cells and the charge: refreshed when either changes.
/obj/machinery/power/smes/batteryrack/proc/sync_look()
	set_shown_overlays(jointext(rack_overlays(), ","))

// ---- the window ----

/obj/machinery/power/smes/batteryrack/ui_data(datum/act/eval/A)
	var/list/cells = list()
	var/cell_index = 0
	for(var/obj/item/cell/C in internal_cells)
		var/list/cell[0]
		cell["slot"] = cell_index + 1
		cell["used"] = 1
		cell["percentage"] = round(C.percent(), 0.01)
		cell["name"] = C.name
		cell["id"] = C.c_uid
		cell_index++
		cells += list(cell)
	while(cell_index < PSU_MAXCELLS)
		var/list/cell[0]
		cell["slot"] = cell_index + 1
		cell["used"] = 0
		cell_index++
		cells += list(cell)
	return list(
		"mode" = mode,
		"transfer_max" = max_transfer_rate,
		"output_load" = 0,
		"input_load" = 0,
		"equalise" = equalise,
		"blink_tick" = ui_tick,
		"cells_max" = max_cells,
		"cells_cur" = length(internal_cells),
		"cells_list" = cells)

/// The disable button: input and output both off.
/obj/machinery/power/smes/batteryrack/proc/ui_disable(datum/act/op/A)
	update_io(0)
	return OP_OK

/// The enable button: the mode is the number sent, clamped to the three modes.
/obj/machinery/power/smes/batteryrack/proc/ui_enable(datum/act/op/A, enable)
	update_io(clamp(enable, 1, 3))
	return OP_OK

/// The eject button: the cell with that id comes out onto the rack's tile.
/obj/machinery/power/smes/batteryrack/proc/ui_eject_cell(datum/act/op/A, ejectcell)
	var/obj/item/cell/C
	for(var/obj/item/cell/CL in internal_cells)
		if(CL.c_uid == ejectcell)
			C = CL
			break

	if(!istype(C))
		return OP_OK

	C.forceMove(get_turf(src))
	own_take_member(src, nameof(/obj/machinery/power/smes/batteryrack::internal_cells), C)
	RefreshParts()
	update_maxcharge()
	sync_look()
	return OP_OK

// Recalculate maxcharge and similar variables.
/obj/machinery/power/smes/batteryrack/proc/update_maxcharge()
	var/newmaxcharge = 0
	for(var/obj/item/cell/C in internal_cells)
		newmaxcharge += C.maxcharge

	newmaxcharge /= CELLRATE		// Convert to Joules
	newmaxcharge *= SMESRATE		// And to SMES charge units (which are for some reason different than CELLRATE)
	set_capacity(newmaxcharge)
	set_stored_charge(clamp(stored_charge(), 0, newmaxcharge))

// Sets input/output depending on our "mode" var.
/obj/machinery/power/smes/batteryrack/proc/update_io(newmode)
	set_mode(newmode)
	switch(mode)
		if(PSU_OFFLINE)
			set_input_attempt(0)
			set_output_attempt(0)
		if(PSU_INPUT)
			set_input_attempt(1)
			set_output_attempt(0)
		if(PSU_OUTPUT)
			set_input_attempt(0)
			set_output_attempt(1)
		if(PSU_AUTO)
			set_input_attempt(1)
			set_output_attempt(1)

// Store charge in the power cells, instead of using the charge var. Amount is in joules.
/obj/machinery/power/smes/batteryrack/add_charge(amount)
	amount *= CELLRATE // Convert to CELLRATE first.
	if(equalise)
		// Now try to get least charged cell and use the power from it.
		var/obj/item/cell/CL = get_least_charged_cell()
		if(!CL)
			return
		amount -= CL.give(amount)
		if(!amount)
			return
	// We're still here, so it means the least charged cell was full OR we don't care about equalising the charge. Give power to other cells instead.
	for(var/obj/item/cell/C in internal_cells)
		amount -= C.give(amount)
		// No more power to input so return.
		if(!amount)
			return

/obj/machinery/power/smes/batteryrack/remove_charge(amount)
	amount *= CELLRATE // Convert to CELLRATE first.
	if(equalise)
		// Now try to get most charged cell and use the power from it.
		var/obj/item/cell/CL = get_most_charged_cell()
		if(!CL)
			return
		amount -= CL.use(amount)
		if(!amount)
			return
	// We're still here, so it means the most charged cell didn't have enough power OR we don't care about equalising the charge. Use power from other cells instead.
	for(var/obj/item/cell/C in internal_cells)
		amount -= C.use(amount)
		// No more power to output so return.
		if(!amount)
			return

// Helper procs to get most/least charged cells.
/obj/machinery/power/smes/batteryrack/proc/get_most_charged_cell()
	var/obj/item/cell/CL = null
	for(var/obj/item/cell/C in internal_cells)
		if(CL == null)
			CL = C
		else if(CL.percent() < C.percent())
			CL = C
	return CL
/obj/machinery/power/smes/batteryrack/proc/get_least_charged_cell()
	var/obj/item/cell/CL = null
	for(var/obj/item/cell/C in internal_cells)
		if(CL == null)
			CL = C
		else if(CL.percent() > C.percent())
			CL = C
	return CL

/obj/machinery/power/smes/batteryrack/proc/insert_cell(obj/item/cell/C, mob/user)
	if(!istype(C))
		return 0

	if(length(internal_cells) >= max_cells)
		return 0

	if(!move_into(src, nameof(src.internal_cells), C, user))
		return 0
	RefreshParts()
	update_maxcharge()
	sync_look()
	return 1

/// There is a free slot for another cell.
/obj/machinery/power/smes/batteryrack/proc/cell_room(datum/act/A)
	return (length(internal_cells) < max_cells) ? null : MSG(batteryrack/full)

/// The cell in hand goes into the rack.
/obj/machinery/power/smes/batteryrack/proc/cell_inserted(datum/act/op/A)
	return insert_cell(A.held, A.actor) ? OP_OK : OP_REFUSED

/// A rack re-reads its cells and balances them every frame (it never idles), then shows what they look like.
/obj/machinery/power/smes/batteryrack/proc/power_frame(datum/act/timer/A)
	power_step()

/obj/machinery/power/smes/batteryrack/proc/power_step()
	var/cell_charge = 0
	for(var/obj/item/cell/C in internal_cells)
		cell_charge += C.charge
	cell_charge /= CELLRATE		// Convert to Joules
	cell_charge *= SMESRATE		// And to SMES charge units (which are for some reason different than CELLRATE)
	set_stored_charge(cell_charge)

	set_ui_tick(!ui_tick)
	balance_cells()
	sync_look()

/// Try to balance charge between stored cells. Capped at max_transfer_rate per tick.
/// Take power from most charged cell, and give it to least charged cell.
/obj/machinery/power/smes/batteryrack/proc/balance_cells()
	if(equalise)
		var/obj/item/cell/least = get_least_charged_cell()
		var/obj/item/cell/most = get_most_charged_cell()
		// Don't bother equalising charge between two same cells. Also ensure we don't get NULLs or wrong types. Don't bother equalising when difference between charges is tiny.
		if(least == most || !istype(least) || !istype(most) || least.percent() == most.percent())
			return
		var/percentdiff = (most.percent() - least.percent()) / 2 // Transfer only 50% of power. The reason is that it could lead to situations where least and most charged cells would "swap places" (45->50% and 50%->45%)
		var/celldiff
		// Take amount of power to transfer from the cell with smaller maxcharge
		if(most.maxcharge > least.maxcharge)
			celldiff = (least.maxcharge / 100) * percentdiff
		else
			celldiff = (most.maxcharge / 100) * percentdiff
		celldiff = clamp(celldiff, 0, max_transfer_rate * CELLRATE)
		// Ensure we don't transfer more energy than the most charged cell has, and that the least charged cell can input.
		celldiff = min(min(celldiff, most.charge), least.maxcharge - least.charge)
		least.give(most.use(celldiff))

/obj/machinery/power/smes/batteryrack/dismantle()
	for(var/obj/item/cell/C in internal_cells)
		C.forceMove(get_turf(src))
		own_take_member(src, nameof(internal_cells), C)
	return ..()

/// The rack's input and output follow its mode (set from its window), never the SMES's own toggles: these do nothing, whoever asks.
/obj/machinery/power/smes/batteryrack/set_input_on(on)
	return

/obj/machinery/power/smes/batteryrack/set_output_on(on)
	return

#undef PSU_OFFLINE
#undef PSU_OUTPUT
#undef PSU_INPUT
#undef PSU_AUTO

#undef PSU_MAXCELLS

/obj/machinery/power/smes/batteryrack/mapped
	var/cell_type = /obj/item/cell/apc
	var/cell_number = 3

/obj/machinery/power/smes/batteryrack/mapped/Initialize(mapload)
	. = ..()
	for(var/i = 1 to cell_number)
		if(i > max_cells)
			break
		var/obj/item/cell/newcell = new cell_type(src.loc)
		insert_cell(newcell)

/obj/item/module/power_control/multitool_act(mob/user, obj/item/I)
	use_tool(user, I, src, delay = 5 SECONDS, start_self = "You begin tweaking the power control circuits to support a power cell rack.", receiver = src, on_done = PROC_REF(multitool_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/item/module/power_control/proc/multitool_act_tool_done(mob/user)
	var/obj/item/newcircuit = replace_with(src, /obj/item/circuitboard/batteryrack)
	user.put_in_hands(newcircuit)
