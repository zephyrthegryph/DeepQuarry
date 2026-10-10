// The fabricator capability (doc/rewrite/final_api.html, section 11 "The library": fabricator(buildtypes =, efficiency =); section 16.14) and the
// dismantle graph of a machine built from a circuit board.
//
// A fabricator prints designs from its material store. What every one of them shares is here, declared once:
//
//   the print run      op "print" (a window button: `action`, with the design in `design_arg` and the count in `count_arg`). Its refusals are
//                      requirements: one run at a time, a design the machine knows (`knows`: a holder proc x(datum/design_techweb/D)) and has the
//                      manipulators for (`buildtypes`: the flags, or the holder var that holds them), a valid material choice, the materials for the whole run (`efficiency`: the holder var of
//                      its cost coefficient; a stack costs exactly its materials). The run is a keyed timer chain on the holder ("fabricator.print"):
//                      one item every `build_time` (a holder proc x(datum/design_techweb/D)) while the machine works and has the power and the
//                      materials; it stops, says why, and the machine is free again. State key FABRICATOR_PRINTING (fabricator_printing(holder)).
//                      The run is a /datum/fab_run the holder owns in its `run_var` var (owns_one(nameof(print_run), /datum/fab_run)).
//   the drop rule      the holder var `drop` (drop_direction): dragging the machine onto a tile points it there (not while it prints), alt-click forgets
//                      it (`resets`), and a print lands on that tile unless the tile is blocked (fabricator_drop_turf()), else on the machine's.
//   the store          `materials` names the holder var of its /datum/material_container or /datum/remote_materials (an ore silo link); an
//                      item used on the shut machine goes to the store's own use gate (op "store", just above the window);
//                      `eject` adds the "remove_mat" button that takes sheets back out (`eject_power`: it costs power as the lathes' did).
//   examine            what the materials cost, and where printed things drop.
//
// `print` = FALSE keeps the drop rule, the store and examine without the run (the exosuit fabricator builds a queue of its own).
//
//   fabricator(buildtypes = AUTOLATHE, efficiency = nameof(creation_efficiency), action = "make", design_arg = "id", count_arg = "multiplier",
//       knows = PROC_REF(knows_design), build_time = PROC_REF(design_build_time))

MSG_DEF_SELF(fabricator/idle, "It isn't printing anything.")
MSG_DEF_SELF(fabricator/busy, "It is busy. Wait for the current print run to finish.")
MSG_DEF_SELF(fabricator/unknown_design, "It does not know that design.")
MSG_DEF_SELF(fabricator/no_keys, "It does not have the necessary manipulation systems for that design.")
MSG_DEF_SELF(fabricator/choose_materials, "Select valid materials for every required construction slot.")
MSG_DEF_SELF(fabricator/no_materials, "There are not enough materials for that.")
MSG_DEF_SELF(fabricator/on_hold, "Its access to the material storage is on hold.")
MSG_DEF_SELF(fabricator/printing, "Not while it is printing.")
MSG_DEF_SELF(fabricator/no_power, "It doesn't have the power to dispense sheets.")
MSG_DEF_SELF(fabricator/no_such_material, "It holds no such material.")
MSG_DEF_SELF(fabricator/too_far, "You need to stand next to it.")

CAPABILITY_TYPE(fabricator, CAP_FABRICATOR, /datum/capability/lib/fabricator, key = NONE, buildtypes = NONE, efficiency = null, materials = "materials", print = TRUE, action = "build", design_arg = "ref", count_arg = "amount", knows = null, build_time = null, department = null, worth_floor = 10, sound = "print_sound", resets = TRUE, eject = FALSE, eject_power = FALSE, drop = "drop_direction", run_var = "print_run")
cap_keys(CAP_FABRICATOR, PRINTING = MSG(fabricator/idle))

/// The most of one design a single run prints.
#define FABRICATOR_MAX_RUN 50
/// The timer key of a fabricator's print run.
#define FABRICATOR_RUN_KEY "fabricator.print"

/datum/capability/lib/fabricator

/datum/capability/lib/fabricator/entries()
	. = list(
		op("drop_here", at_target(), gesture(GESTURE_DRAG), reach(REACH_RANGE(2)), label("Drop printed things here"),
			needs(req_bool(CAP_PROC(beside), because = MSG(fabricator/too_far)), req_bool(CAP_PROC(idle), because = MSG(fabricator/printing))),
			then(CAP_PROC(drop_pointed))),
		// an item used on it goes to its store (sheets, a sheet snatcher, a multitool linking an ore silo), through the store's own use gate
		op("store", item(/obj/item), label("Put it in"), priority(OP_PRIORITY_DEFAULT + 1), when(CAP_PROC(store_reachable)), then(CAP_PROC(store_used))),
		examine_line(CAP_PROC(cost_text)),
		examine_line(CAP_PROC(drop_text)))
	if(resets)
		. += op("reset_drop", hand(), gesture(GESTURE_ALT), label("Reset drop direction"), when(drop),
			needs(req_bool(CAP_PROC(idle), because = MSG(fabricator/printing))), then(CAP_PROC(drop_forgotten)))
	if(print)
		. += op("print", ui_act(action, arg(design_arg, schema_text(256)), arg(count_arg, num(1, FABRICATOR_MAX_RUN)), arg("materialSlots")),
			needs(
				req_bool(CAP_PROC(idle), because = MSG(fabricator/busy)),
				req_bool(CAP_PROC(design_known), because = MSG(fabricator/unknown_design)),
				req_bool(CAP_PROC(design_fits), because = MSG(fabricator/no_keys)),
				req_bool(CAP_PROC(choice_valid), because = MSG(fabricator/choose_materials)),
				req_bool(CAP_PROC(store_open), because = MSG(fabricator/on_hold)),
				req_bool(CAP_PROC(run_affordable), because = MSG(fabricator/no_materials))),
			then(CAP_PROC(run_started)), logs(LOG_GAME))
	if(eject)
		. += op("remove_mat", ui_act(arg("id", schema_text(64)), arg("amount", num(1, MAX_STACK_SIZE))),
			needs(req_bool(CAP_PROC(material_held), because = MSG(fabricator/no_such_material))),
			then(CAP_PROC(sheets_ejected)))

// ---- the print run ----

/// The machine is free: no run is under way.
/datum/capability/lib/fabricator/proc/idle(datum/act/A)
	return !fabricator_printing(A.holder)

/// The design the button names, or null.
/datum/capability/lib/fabricator/proc/asked_design(datum/act/op/A) as /datum/design_techweb
	var/id = A.args ? A.args[design_arg] : null
	return istext(id) ? SSresearch.techweb_design_by_id(id) : null

/// The machine knows the design (its holder proc says so).
/datum/capability/lib/fabricator/proc/design_known(datum/act/op/A)
	var/datum/design_techweb/D = asked_design(A)
	return D && (!knows || call(A.holder, knows)(D))

/// It has the manipulators for it: a design of a build type the machine has (one that names none fits anything).
/datum/capability/lib/fabricator/proc/design_fits(datum/act/op/A)
	var/datum/design_techweb/D = asked_design(A)
	return D && (!D.build_type || (D.build_type & fabricator_buildtypes(A.holder, buildtypes)))

/// The build types a fabricator makes: `buildtypes` is the flags, or the holder var holding them (a subtype sets its own).
/proc/fabricator_buildtypes(datum/holder, buildtypes)
	return istext(buildtypes) ? holder.vars[buildtypes] : buildtypes

/// The materials chosen fill every slot of a design that lets the maker choose.
/datum/capability/lib/fabricator/proc/choice_valid(datum/act/op/A)
	var/datum/design_techweb/D = asked_design(A)
	return D && (!D.material_template || D.material_choice_valid(chosen_of(A)))

/// The store is not on hold (an ore silo can hold a linked machine's access).
/datum/capability/lib/fabricator/proc/store_open(datum/act/op/A)
	var/datum/remote_materials/R = A.holder.vars[materials]
	return !istype(R) || R.can_use_resource()

/// The store holds the materials for the whole run.
/datum/capability/lib/fabricator/proc/run_affordable(datum/act/op/A)
	var/datum/design_techweb/D = asked_design(A)
	var/datum/material_container/C = fabricator_store(A.holder, materials)
	if(!D || !C)
		return FALSE
	var/count = A.args ? A.args[count_arg] : null
	return C.has_materials(needed_of(D, chosen_of(A)), coefficient_of(A.holder, D), isnum(count) ? count : 1)

/// The material choice the button sent (a list of slot -> material name), or an empty one.
/datum/capability/lib/fabricator/proc/chosen_of(datum/act/op/A)
	var/list/slots = A.args ? A.args["materialSlots"] : null
	return islist(slots) ? slots : list()

/// The materials one item of `D` takes (with the maker's choice), keyed by material datum.
/datum/capability/lib/fabricator/proc/needed_of(datum/design_techweb/D, list/chosen)
	. = list()
	var/list/effective = D.effective_materials(chosen)
	for(var/id in effective)
		var/datum/material/M = istype(id, /datum/material) ? id : get_material_by_name(id)
		if(istype(M))
			.[M] += effective[id]

/// The cost coefficient of `D`: the machine's efficiency, except for a stack, which costs exactly its materials.
/datum/capability/lib/fabricator/proc/coefficient_of(datum/holder, datum/design_techweb/D)
	if(ispath(D.build_path, /obj/item/stack) || !efficiency)
		return 1
	return holder.vars[efficiency]

/// The run begins: the first item comes after one build time.
/datum/capability/lib/fabricator/proc/run_started(datum/act/op/A, design_id, count, slots)
	var/obj/machinery/M = A.holder
	var/datum/design_techweb/D = asked_design(A)
	var/datum/fab_run/run = new
	run.design = D
	run.remaining = isnum(count) ? count : 1
	run.chosen = chosen_of(A)
	run.needed = needed_of(D, run.chosen)
	run.coefficient = coefficient_of(M, D)
	run.build_time = build_time ? call(M, build_time)(D) : D.construction_time
	var/charge = 0
	for(var/datum/material/mat as anything in run.needed)
		charge += run.needed[mat]
	run.charge = ROUND_UP((charge / (MAX_STACK_SIZE * SHEET_MATERIAL_AMOUNT)) * run.coefficient * M.active_power_usage)
	var/obj/item/card/id/card = A.actor?.GetIdCard()
	run.producer_account = card?.associated_account_number || 0
	run.department = department || department_for_mob(A.actor) || DEPARTMENT_ENGINEERING
	run.worth_floor = worth_floor
	run.materials = materials
	run.sound = sound
	run.drop = drop
	rel_set(M, run_var, run)
	cap_key_set(M, FABRICATOR_PRINTING, TRUE, null)
	var/datum/looping_sound/loop = sound ? M.vars[sound] : null
	loop?.start()
	after(M, run.build_time, GLOBAL_PROC_REF(fabricator_print_step), key = FABRICATOR_RUN_KEY, with = list(M, run_var))
	return OP_OK

/// One print run: what it makes, how many are left, and what each costs.
/datum/fab_run
	var/datum/design_techweb/design
	var/remaining = 0
	var/build_time = 1 SECOND
	var/coefficient = 1
	/// Power for one item.
	var/charge = 0
	/// Material datum -> amount for one item.
	var/list/needed
	/// The maker's material choice (slot -> material name).
	var/list/chosen
	var/producer_account = 0
	var/department
	/// The least worth a printed item carries (its build time in seconds above it).
	var/worth_floor = 10
	/// The holder vars of its store, its sound and its drop direction.
	var/materials
	var/sound
	var/drop

/// One item of the run (the one the holder owns in `run_var`), then the next after a build time, until the run is done or something stops it.
/proc/fabricator_print_step(obj/machinery/M, run_var)
	if(!M || QDELETED(M))
		return
	var/datum/fab_run/run = M.vars[run_var]
	if(!run)
		return
	var/why = fabricator_print_one(M, run)
	if(why)
		M.atom_say(why)
	if(why || run.remaining <= 0)
		fabricator_run_ended(M, run_var)
		return
	after(M, run.build_time, GLOBAL_PROC_REF(fabricator_print_step), key = FABRICATOR_RUN_KEY, with = list(M, run_var))

/// Makes the next item (a stack design makes the whole run at once) onto the drop tile. Returns why it could not, or null.
/proc/fabricator_print_one(obj/machinery/M, datum/fab_run/run)
	if(!M.operable())
		return "Unable to continue production, power failure."
	if(!M.use_power_oneoff(run.charge))
		var/area/A = get_area(M)
		return QDELETED(A?.apc) ? "Unable to continue production, no APC in area." : "Unable to continue production, power grid overload."
	var/datum/material_container/C = fabricator_store(M, run.materials)
	var/datum/remote_materials/R = M.vars[run.materials]
	if(istype(R) && !R.can_use_resource())
		return "Unable to continue production, materials on hold."
	var/datum/design_techweb/D = run.design
	var/is_stack = ispath(D.build_path, /obj/item/stack)
	var/count = is_stack ? run.remaining : 1
	if(!C || !C.has_materials(run.needed, run.coefficient, count))
		return "Unable to continue production, missing materials."
	if(istype(R))
		R.use_materials(run.needed, run.coefficient, count, "built", "[D.name]")
	else
		C.use_materials(run.needed, run.coefficient, count)
	var/turf/target = fabricator_drop_turf(M, run.drop) || get_turf(M)
	var/worth = max(run.worth_floor, run.build_time / 10)
	if(is_stack)
		var/obj/item/stack/stack_type = D.build_path
		var/max_amount = initial(stack_type.max_amount)
		var/to_make = initial(stack_type.amount) * run.remaining
		while(to_make > 0)
			// made in nullspace: a stack that lands on a tile merges with its kind (and may be deleted)
			var/obj/item/stack/S = new stack_type(null, min(to_make, max_amount))
			fabricator_place(S, target, run, worth)
			to_make -= max_amount
		run.remaining = 0
		return null
	var/atom/movable/made = D.create_item(null, run.chosen)
	split_materials_uniformly(run.needed, run.coefficient, made)
	fabricator_place(made, target, run, worth)
	run.remaining--
	return null

/// A printed thing lands on `target`, a little off centre, carrying who made it.
/proc/fabricator_place(atom/movable/made, turf/target, datum/fab_run/run, worth)
	if(isitem(made))
		var/obj/item/I = made
		I.pixel_x = rand(-6, 6)
		I.pixel_y = rand(-6, 6)
		I.set_economic_provenance(run.department, worth, run.producer_account)
	made.forceMove(target)

/// The run is over: the machine is free and quiet, and the run it owned is gone.
/proc/fabricator_run_ended(obj/machinery/M, run_var)
	cancel_after(M, FABRICATOR_RUN_KEY)
	var/datum/fab_run/run = M.vars[run_var]
	cap_key_set(M, FABRICATOR_PRINTING, FALSE, null)
	var/datum/looping_sound/loop = run?.sound ? M.vars[run.sound] : null
	loop?.stop()
	rel_clear(M, run_var)

/// The material container behind a fabricator's store var (its own, or its silo link's).
/proc/fabricator_store(datum/holder, materials) as /datum/material_container
	var/datum/store = holder.vars[materials]
	if(istype(store, /datum/remote_materials))
		var/datum/remote_materials/R = store
		return R.mat_container()
	return store

// ---- where printed things drop ----

/// The tile a fabricator drops onto: the one in its drop direction (the holder var `drop`), or its own with none; null when that tile is blocked.
/proc/fabricator_drop_turf(obj/machinery/M, drop)
	var/direction = M.vars[drop]
	if(!direction)
		return get_turf(M)
	var/turf/T = get_step(M, direction)
	if(!T || T.density)
		return null
	return T

/// The actor stands next to the machine it drags (the tile it points at may be a step further).
/datum/capability/lib/fabricator/proc/beside(datum/act/op/A)
	var/atom/movable/M = A.holder
	return A.actor && M.Adjacent(A.actor)

/// Dragged onto a tile, the machine drops printed things toward it.
/datum/capability/lib/fabricator/proc/drop_pointed(datum/act/op/A)
	var/atom/movable/M = A.holder
	var/direction = get_dir(M, get_turf(A.target))
	if(!direction)
		return OP_REFUSED
	op_write_key(M, drop, direction)
	M.balloon_alert(A.actor, "dropping [dir2text(direction)]")
	return OP_OK

/// Alt-click: it drops on its own tile again.
/datum/capability/lib/fabricator/proc/drop_forgotten(datum/act/op/A)
	var/atom/movable/M = A.holder
	op_write_key(M, drop, 0)
	M.balloon_alert(A.actor, "drop direction reset")
	return OP_OK

// ---- the store's sheets ----

/// The store takes items while the panel is shut; the panel's tools are the machine's, not the store's (a crowbar on the shut panel is refused, not
/// melted down), except a multitool on a store that links to an ore silo.
/datum/capability/lib/fabricator/proc/store_reachable(datum/act/op/A)
	if(panel_open(A.holder))
		return FALSE
	var/obj/item/I = A.held
	if(I.has_tool_quality(TOOL_SCREWDRIVER) || I.has_tool_quality(TOOL_CROWBAR) || I.has_tool_quality(TOOL_WIRECUTTER))
		return FALSE
	if(I.has_tool_quality(TOOL_MULTITOOL))
		return istype(A.holder.vars[materials], /datum/remote_materials)
	return TRUE

/// The held item goes through the store's use gate (the material container's or the silo link's hook on the item use); a store that does not
/// want it lets the click go on.
/datum/capability/lib/fabricator/proc/store_used(datum/act/op/A)
	return attackby_stopped(A.holder, A.held, A.actor) ? OP_OK : OP_DECLINE

/// The button names a material the store holds.
/datum/capability/lib/fabricator/proc/material_held(datum/act/op/A)
	var/datum/material/M = fabricator_material(A.args ? A.args["id"] : null)
	var/datum/material_container/C = fabricator_store(A.holder, materials)
	return istype(M) && C && C.get_material_amount(M) > 0

/// Sheets of the material come out onto the machine's tile.
/datum/capability/lib/fabricator/proc/sheets_ejected(datum/act/op/A, id, amount)
	var/obj/machinery/M = A.holder
	var/datum/material/mat = fabricator_material(id)
	// insertion takes 40% of the base power per full stack, and so does taking sheets back out (the base power: better parts draw more for nothing)
	if(eject_power && !M.use_power_oneoff(ROUND_UP((amount / MAX_STACK_SIZE) * 0.4 * initial(M.active_power_usage))))
		M.atom_say("No power to dispense sheets")
		return OP_REFUSED
	var/datum/remote_materials/R = M.vars[materials]
	if(istype(R))
		R.eject_sheets(mat, amount)
	else
		var/datum/material_container/C = M.vars[materials]
		C.retrieve_sheets(amount, mat, get_turf(M))
	return OP_OK

/// The material a window names: by its name, else by whatever GET_MATERIAL_REF() takes.
/proc/fabricator_material(id) as /datum/material
	if(!istext(id))
		return null
	var/datum/material/M = GLOB.name_to_material[id]
	return istype(M) ? M : GET_MATERIAL_REF(id)

// ---- examine ----

/datum/capability/lib/fabricator/proc/cost_text(datum/act/A)
	if(!efficiency)
		return null
	return span_notice("Material usage cost at <b>[A.holder.vars[efficiency] * 100]%</b>.")

/datum/capability/lib/fabricator/proc/drop_text(datum/act/A)
	var/direction = A.holder.vars[drop]
	if(!direction)
		return span_notice("Drag towards a direction (while next to it) to change drop direction.")
	. = list(span_notice("Currently configured to drop printed objects <b>[dir2text(direction)]</b>."))
	if(resets)
		. += span_notice("Alt-click to reset.")

// ---- the window ----

/// The window row of one design: name, text, cost at `coefficient`, categories, icon and its material slots.
/proc/fabricator_design_row(datum/design_techweb/D, coefficient)
	var/datum/asset/spritesheet_batched/research_designs/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	var/list/cost = list()
	var/coeff = ispath(D.build_path, /obj/item/stack) ? 1 : coefficient
	for(var/id in D.materials)
		var/datum/material/M = istype(id, /datum/material) ? id : get_material_by_name(id)
		cost[istype(M) ? M.name : "[id]"] = OPTIMAL_COST(D.materials[id] * coeff)
	var/css_id = sanitize_css_class_name(D.id)
	var/size = spritesheet.icon_size_id(css_id)
	return list(
		"name" = D.name,
		"desc" = D.get_description(),
		"cost" = cost,
		"id" = D.id,
		"categories" = D.category,
		"icon" = "[size == "[spritesheet.name]32x32" ? "" : "[size] "][css_id]",
		"materialConfigurable" = !!D.material_template,
		"materialProfile" = D.material_application,
		"materialSlots" = material_slots_tgui(material_template_singleton(D.material_template), D.material_total),
	)

// ---------------------------------------------------------------------------------------------------------------------
// A machine built from a circuit board
// ---------------------------------------------------------------------------------------------------------------------

STAGE_DEF(board_machine, built)
MSG_DEF_SELF(stage/board_machine/built, "It is assembled.")

/// The dismantle graph of a machine built in a frame from a circuit board: behind its open panel a crowbar takes it apart into the frame, its board
/// and its parts at once (dismantle()). machine_basics(frame = board_machine()) takes it; the machine declares the panel (panel()).
/proc/board_machine()
	return construction(start(STAGE_BOARD_MACHINE_BUILT), at(SPACE_PANEL),
		dismantle(tool(TOOL_CROWBAR), wait(0), then(TYPE_PROC_REF(/obj/machinery, dismantled_into_frame))))

/// The crowbar's work: the frame, the board and the parts stand where the machine stood (it is gone after this).
/obj/machinery/proc/dismantled_into_frame(datum/act/op/A)
	dismantle()
	return OP_OK
