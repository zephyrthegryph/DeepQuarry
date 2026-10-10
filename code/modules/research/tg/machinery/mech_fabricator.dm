// The exosuit fabricator (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md), and the prosthetics fabricator built on it.
//
// ONE CAPABILITIES list says what it is: a machine built from a board (behind the open panel a crowbar takes it apart: board_machine()), a
// screwdriver panel, a part-replacer target (not while a part is made), a fabricator's store, drop rule, sheets button and examine (fabricator(),
// without its print run: this machine builds a queue), and the window's queue buttons. The queue runs on timers: a part takes its build time
// ("exofab_part"), drops out of the exit, and the next starts while the queue runs; a part whose exit is blocked is held and tried again every
// second, and the queue waits for it. The imperative parts below are its own: the queue, the parts, the techweb designs, the window's data and
// the look.

MSG_DEF_SELF(exofab/processing, "It is currently processing! Please wait until completion.")

/obj/machinery/mecha_part_fabricator_tg
	icon = 'icons/obj/machines/robotics.dmi'
	icon_state = "fab-idle"
	name = "exosuit fabricator"
	desc = "Nothing is being built."
	anchored = TRUE
	density = TRUE
	req_access = list(ACCESS_ROBOTICS)
	circuit = /obj/item/circuitboard/mechfab

	/// Type of designs to grab
	var/fab_type = MECHFAB

	/// Current items in the build queue.
	var/list/datum/design_techweb/queue = list() // ALLOW(instance_list): d: the build queue; kept index-parallel with queue_producer_accounts
	/// Producer account parallel to each queued design.
	var/list/queue_producer_accounts = list() // ALLOW(instance_list): d: kept index-parallel with queue (Cut() by index)
	var/current_producer_account = 0

	/// The job ID of the part currently being processed. This is used for ordering list items for the client UI.
	var/top_job_id = 0

	/// Coefficient for the speed of item building. Based on the installed parts.
	var/time_coeff = 1

	/// Coefficient for the efficiency of material usage in item building. Based on the installed parts.
	var/component_coeff = 1

	/// Reference to the techweb.
	var/tmp/datum/techweb/stored_research_static

	/// Reference to a remote material inventory, such as an ore silo.
	var/datum/remote_materials/rmat

	/// All designs in the techweb that can be fabricated by this machine, since the last update.
	var/list/datum/design_techweb/available_designs

	/// Looping sound for printing items
	var/datum/looping_sound/lathe_print/print_sound

	/// Local designs that only this mechfab have(using when mechfab emaged so it's illegal designs).
	var/list/datum/design_techweb/illegal_local_designs

	/// Direction the produced items will drop (0 means on top of us)
	var/drop_direction = SOUTH

	/// The queue is being built, one part after another.
	var/process_queue = FALSE
	/// A finished part held because its exit was blocked.
	var/obj/item/stored_part
	/// The design of the part being made now.
	var/datum/design_techweb/being_built
	/// How long the part being made takes in all (its timer is "exofab_part").
	var/part_time = 0

TRACKED(/obj/machinery/mecha_part_fabricator_tg, process_queue)

CAPABILITIES(/obj/machinery/mecha_part_fabricator_tg)
	machine_basics(repair = NONE, frame = board_machine())
	owns_one(nameof(print_sound), /datum/looping_sound/lathe_print, starts = PROC_REF(make_print_sound))
	owns_one(nameof(rmat), /datum/remote_materials)
	owns_one(nameof(stored_part), /obj/item, on_destroy = ON_DESTROY_SPILL)
	panel()
	extend("panel.open", wait(0))
	part_replacement()
	extend("part_replacement.replace", needs(req_is(FABRICATOR_PRINTING, FALSE, because = MSG(exofab/processing))))
	fabricator(buildtypes = nameof(fab_type), efficiency = nameof(component_coeff), materials = nameof(rmat), print = FALSE, resets = FALSE, eject = TRUE)
	examine_line(PROC_REF(status_text))
	on_change(nameof(process_queue), ENTER, then(PROC_REF(queue_started)))
	every(1 SECOND, then(PROC_REF(release_stored_part)), when = nameof(stored_part))

	section(window, "The window: the designs, the queue and its buttons")
	interface("ExosuitFabricatorTg")
	op("build", ui_act(arg("designs", list_of(schema_text(256))), arg("now", bool())), then(PROC_REF(ui_act_build)))
	op("del_queue_part", ui_act(arg("index", int(1, 1000))), then(PROC_REF(ui_act_del_queue_part)))
	op("clear_queue", ui_act(), then(PROC_REF(ui_act_clear_queue)))
	op("build_queue", ui_act(), sets(nameof(process_queue), TRUE))
	op("stop_queue", ui_act(), sets(nameof(process_queue), FALSE))

/obj/machinery/mecha_part_fabricator_tg/Initialize(mapload)
	// ALLOW(decl): mapload is a constructor argument of its store: only a machine the map places links to the ore silo
	rel_set(src, nameof(rmat), new /datum/remote_materials(src, mapload, mat_container_events = list((/datum/notice/matcontainer_item_consumed) = TYPE_PROC_REF(/obj/machinery/mecha_part_fabricator_tg, on_material_insert))))
	available_designs = list()
	illegal_local_designs = list()
	. = ..()
	default_apply_parts()
	RefreshParts()
	if(!stored_research())
		var/datum/techweb/connected_web
		CONNECT_TO_RND_SERVER_ROUNDSTART(connected_web, src)
		stored_research_static = connected_web
	if(stored_research())
		on_connected_techweb()

/obj/machinery/mecha_part_fabricator_tg/proc/make_print_sound(current)
	return new /datum/looping_sound/lathe_print(list(src), FALSE)

/obj/machinery/mecha_part_fabricator_tg/proc/connect_techweb(datum/techweb/new_techweb)
	if(stored_research())
		unobserve(stored_research(), /datum/notice/techweb_add_design, src)
		unobserve(stored_research(), /datum/notice/techweb_remove_design, src)
	stored_research_static = new_techweb
	if(!isnull(stored_research()))
		on_connected_techweb()

/obj/machinery/mecha_part_fabricator_tg/proc/on_connected_techweb()
	observe(stored_research(), /datum/notice/techweb_add_design, src, then(PROC_REF(on_techweb_update)))
	observe(stored_research(), /datum/notice/techweb_remove_design, src, then(PROC_REF(on_techweb_update)))
	update_menu_tech()

/// Designs come and go in bursts: one refresh two seconds after the first of them.
/obj/machinery/mecha_part_fabricator_tg/proc/on_techweb_update(datum/act/notice/A)
	after(src, 2 SECONDS, PROC_REF(update_menu_tech), key = "mecha_fabricator_tech_menu")

/obj/machinery/mecha_part_fabricator_tg/RefreshParts()
	. = ..()
	var/T = get_part_rating(/obj/item/stock_parts/matter_bin)

	//maximum stocking amount (default 300000, 600000 at T4)
	rmat.set_local_size(((100 * SHEET_MATERIAL_AMOUNT) + (T * (25 * SHEET_MATERIAL_AMOUNT))))

	//resources adjustment coefficient (1 -> 0.85 -> 0.7 -> 0.55)
	T = 1.15 - get_part_rating(/obj/item/stock_parts/micro_laser) * 0.15
	component_coeff = T

	//building time adjustment coefficient (1 -> 0.8 -> 0.6)
	T = get_part_rating(/obj/item/stock_parts/manipulator) - 1
	time_coeff = round(initial(time_coeff) - (initial(time_coeff)*(T))/5,0.01)

	// The part being made finishes as much sooner or later as the new parts make it.
	if(being_built && part_time > 0)
		var/new_time = get_construction_time_w_coeff(initial(being_built.construction_time))
		var/left = after_left(src, "exofab_part")
		after(src, round((new_time / part_time) * left), PROC_REF(part_finished), key = "exofab_part")
		part_time = new_time

	update_static_data_for_all_viewers()

/obj/machinery/mecha_part_fabricator_tg/proc/status_text(datum/act/A)
	return span_notice("The status display reads: Storing up to <b>[rmat.local_size]</b> material units.<br>Material consumption at <b>[component_coeff*100]%</b>.<br>Build time reduced by <b>[100-time_coeff*100]%</b>.")

/**
 * Updates the `final_sets` and `buildable_parts` for the current mecha fabricator.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/update_menu_tech()
	var/previous_design_count = available_designs.len

	available_designs.Cut()
	for(var/v in stored_research().researched_designs)
		var/datum/design_techweb/design = SSresearch.techweb_design_by_id(v)

		if(design.build_type & fab_type)
			available_designs |= design

	for(var/datum/design_techweb/illegal_disign in illegal_local_designs)
		available_designs |= illegal_disign

	var/design_delta = available_designs.len - previous_design_count

	if(design_delta > 0)
		atom_say("Received [design_delta] new design[design_delta == 1 ? "" : "s"].")
		play_sfx(src, SFX_MACHINES_TWOBEEP)

	update_static_data_for_all_viewers()

// ---- the queue ----

/// The queue was started: the first part begins unless one is being made or held.
/obj/machinery/mecha_part_fabricator_tg/proc/queue_started(datum/act/A)
	if(!being_built && !stored_part)
		start_next()

/// The next part of the queue begins; with nothing left (or nothing it can build) the queue stops.
/obj/machinery/mecha_part_fabricator_tg/proc/start_next(verbose = TRUE)
	var/turf/exit = get_step(src, drop_direction)
	if(!exit || exit.density)
		if(verbose)
			atom_say("Warning. Exit port obstructed. Please clear obstructions or reorient machine, then retry.")
		on_finish_printing()
		return FALSE
	if(!build_next_in_queue(verbose))
		on_finish_printing()
		return FALSE
	on_start_printing()
	return TRUE

/**
 * Intended to be called when an item starts printing.
 *
 * Sets active power usage settings.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/on_start_printing()
	set_use_power(USE_POWER_ACTIVE)
	print_sound.start()

/**
 * Intended to be called when the exofab has stopped working and is no longer printing items.
 *
 * Sets idle power usage settings. Additionally resets the description and turns off queue processing.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/on_finish_printing()
	set_use_power(USE_POWER_IDLE)
	desc = initial(desc)
	set_process_queue(FALSE)
	print_sound.stop()

/**
 * Attempts to build the next item in the build queue.
 *
 * Returns FALSE if either there are no more parts to build or the next part is not buildable.
 * Returns TRUE if the next part has started building.
 * * verbose - Whether the machine should use atom_say() procs. Set to FALSE to disable the machine saying reasons for failure to build.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/build_next_in_queue(verbose = TRUE)
	if(!length(queue))
		return FALSE

	var/datum/design_techweb/D = queue[1]
	if(build_part(D, verbose, queue_producer_accounts[1]))
		remove_from_queue(1)
		return TRUE

	return FALSE

/**
 * Starts the build process for a given design datum.
 *
 * Returns FALSE if the procedure fails. Returns TRUE when being_built is set.
 * Uses materials.
 * * D - Design datum to attempt to print.
 * * verbose - Whether the machine should use atom_say() procs. Set to FALSE to disable the machine saying reasons for failure to build.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/build_part(datum/design_techweb/D, verbose = TRUE, producer_account = 0)
	if(!D || length(D.reagents_list))
		return FALSE

	var/turf/exit = get_step(src, drop_direction)
	if(exit && exit.density)
		if(verbose)
			atom_say("Warning. Exit port obstructed. Please clear obstructions or reorient machine, then retry.")
		return FALSE

	var/datum/material_container/materials = rmat.mat_container()
	if (!materials)
		if(verbose)
			atom_say("No access to material storage, please contact the quartermaster.")
		return FALSE
	if (rmat.on_hold())
		if(verbose)
			atom_say("Mineral access is on hold, please contact the quartermaster.")
		return FALSE
	if(!materials.has_materials(D.materials, component_coeff))
		if(verbose)
			atom_say("Not enough resources. Processing stopped.")
		return FALSE

	rmat.use_materials(D.materials, component_coeff, 1, "built", "[D.name]")
	set_being_built(D)
	cap_key_set(src, FABRICATOR_PRINTING, TRUE, null)
	current_producer_account = producer_account
	part_time = get_construction_time_w_coeff(initial(D.construction_time))
	after(src, part_time, PROC_REF(part_finished), key = "exofab_part")
	desc = "It's building \a [D.name]."

	return TRUE

/// The part is made: it drops out (or is held for a blocked exit), and the queue goes on while it runs and nothing is held.
/obj/machinery/mecha_part_fabricator_tg/proc/part_finished()
	if(!being_built)
		return
	dispense_built_part(being_built)
	if(process_queue && !stored_part)
		if(!build_next_in_queue(FALSE))
			on_finish_printing()
	else if(!process_queue)
		on_finish_printing()

/// A held part tries its exit again: once it is clear the part drops out and the queue goes on.
/obj/machinery/mecha_part_fabricator_tg/proc/release_stored_part(datum/act/A)
	var/turf/exit = get_step(src, drop_direction)
	if(!stored_part || !exit || exit.density)
		return
	atom_say("Obstruction cleared. The fabrication of [stored_part] is now complete.")
	var/obj/item/part = rel_take(src, nameof(stored_part))
	part.forceMove(exit)
	if(process_queue && !being_built)
		start_next(FALSE)

/**
 * Dispenses a part to the tile infront of the Exosuit Fab.
 *
 * Returns FALSE is the machine cannot dispense the part on the appropriate turf.
 * Return TRUE if the part was successfully dispensed.
 * * dispensed_design - Design datum to attempt to dispense.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/dispense_built_part(datum/design_techweb/dispensed_design)
	var/obj/item/built_part = create_new_part(dispensed_design)
	split_materials_uniformly(dispensed_design.materials, component_coeff, built_part)
	built_part.set_economic_provenance(DEPARTMENT_RESEARCH, max(25, dispensed_design.construction_time), current_producer_account)
	current_producer_account = 0

	set_being_built(null)
	cap_key_set(src, FABRICATOR_PRINTING, FALSE, null)
	part_time = 0

	var/turf/exit = get_step(src, drop_direction)
	if(exit.density)
		atom_say("Error! The part outlet is obstructed.")
		desc = "It's trying to dispense the fabricated [dispensed_design.name], but the part outlet is obstructed."
		rel_set(src, nameof(stored_part), built_part)
		return FALSE

	atom_say("The fabrication of [built_part] is now complete.")
	built_part.forceMove(exit)

	top_job_id += 1

	return TRUE

/**
 * Creates parts as necessary (overridden by the prosfab)
 */
/obj/machinery/mecha_part_fabricator_tg/proc/create_new_part(datum/design_techweb/dispensed_design)
	return dispensed_design.create_item(src)

/**
 * Adds a datum design to the build queue.
 *
 * Returns TRUE if successful and FALSE if the design was not added to the queue.
 * * D - Datum design to add to the queue.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/add_to_queue(datum/design_techweb/D, producer_account = 0)
	if(!istype(queue))
		queue = list()

	if(D)
		queue[++queue.len] = D
		queue_producer_accounts += producer_account
		return TRUE

	return FALSE

/**
 * Removes datum design from the build queue based on index.
 *
 * Returns TRUE if successful and FALSE if a design was not removed from the queue.
 * * index - Index in the build queue of the element to remove.
 */
/obj/machinery/mecha_part_fabricator_tg/proc/remove_from_queue(index)
	if(!isnum(index) || !ISINTEGER(index) || !istype(queue) || (index<1 || index>length(queue)))
		return FALSE
	var/end_index = index + 1
	queue.Cut(index, end_index)
	queue_producer_accounts.Cut(index, end_index)
	return TRUE

/**
 * Calculates the coefficient-modified build time of a design.
 *
 * Returns coefficient-modified build time of a given design.
 * * D - Design datum to calculate the modified build time of.
 * * roundto - Rounding value for round() proc
 */
/obj/machinery/mecha_part_fabricator_tg/proc/get_construction_time_w_coeff(construction_time, roundto = 1) //aran
	return round(construction_time*time_coeff, roundto)

// ---- the window ----

/obj/machinery/mecha_part_fabricator_tg/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/sheetmaterials),
		get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	)

/obj/machinery/mecha_part_fabricator_tg/tgui_static_data(mob/user)
	var/list/data = ..()

	var/list/designs = list()

	var/datum/asset/spritesheet_batched/research_designs/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	var/size32x32 = "[spritesheet.name]32x32"

	for(var/datum/design_techweb/design in available_designs)
		var/cost = list()
		var/list/materials = design.materials
		for(var/mat_id in materials)
			cost[mat_id] = OPTIMAL_COST(materials[mat_id] * component_coeff)

		var/css_id = sanitize_css_class_name(design.id)
		var/size = spritesheet.icon_size_id(css_id)
		designs[design.id] = list(
			"name" = design.name,
			"desc" = design.get_description(),
			"cost" = cost,
			"id" = design.id,
			"categories" = design.category,
			"icon" = "[size == size32x32 ? "" : "[size] "][css_id]",
			"constructionTime" = get_construction_time_w_coeff(design.construction_time)
		)

	data["designs"] = designs

	var/list/material_data = rmat.mat_container()?.tgui_static_data(user)
	if(material_data)
		data += material_data

	return data

/obj/machinery/mecha_part_fabricator_tg/ui_data(datum/act/eval/A)
	var/list/data = list("processing" = process_queue)

	var/list/material_data = rmat.mat_container()?.material_list_data(A.actor)
	if(material_data)
		data["materials"] = material_data
	data["queue"] = list()

	if(being_built)
		data["queue"] += list(list(
			"jobId" = top_job_id,
			"designId" = being_built.id,
			"processing" = TRUE,
			"timeLeft" = after_left(src, "exofab_part"),
		))

	var/offset = 0

	for(var/datum/design_techweb/design in queue)
		offset += 1

		data["queue"] += list(list(
			"jobId" = top_job_id + offset,
			"designId" = design.id,
			"processing" = FALSE,
			"timeLeft" = get_construction_time_w_coeff(design.construction_time) / 10
		))

	return data

/// The window's designs go on the queue (only ones it knows and makes); `now` starts it.
/obj/machinery/mecha_part_fabricator_tg/proc/ui_act_build(datum/act/op/A, designs, now)
	var/obj/item/card/id/producer_id = A.actor?.GetIdCard()
	var/producer_account = producer_id?.associated_account_number || 0

	if(!islist(designs))
		return OP_REFUSED

	for(var/design_id in designs)
		if(!istext(design_id))
			continue

		if(!(LAZYFIND(stored_research().researched_designs, design_id) || is_type_in_list(SSresearch.techweb_design_by_id(design_id), illegal_local_designs)))
			continue

		var/datum/design_techweb/design = SSresearch.techweb_design_by_id(design_id)

		if(!(design.build_type & fab_type) || design.id != design_id)
			continue

		add_to_queue(design, producer_account)

	if(now)
		set_process_queue(TRUE)
	return OP_OK

/obj/machinery/mecha_part_fabricator_tg/proc/ui_act_del_queue_part(datum/act/op/A, index)
	remove_from_queue(index)
	return OP_OK

/obj/machinery/mecha_part_fabricator_tg/proc/ui_act_clear_queue(datum/act/op/A)
	queue.Cut()
	queue_producer_accounts.Cut()
	return OP_OK

/// Local material container hook (/datum/om/event/matcontainer_item_consumed).
/obj/machinery/mecha_part_fabricator_tg/proc/on_material_insert(datum/act/notice/N)
	var/datum/notice/matcontainer_item_consumed/event = N
	AfterMaterialInsert(event.item, event.primary_mat, event.material_amount)

/obj/machinery/mecha_part_fabricator_tg/proc/AfterMaterialInsert(item_inserted, id_inserted, amount_inserted)
	flick_overlay_view_atom(mutable_appearance(icon, "fab-load-metal"), 1 SECOND)

// ---- the look ----

/// Its open panel has its own state; it shows its work while a part is made.
TRACKED(/obj/machinery/mecha_part_fabricator_tg, being_built)

/obj/machinery/mecha_part_fabricator_tg/draw(datum/look/look)
	..()
	look.hide(LOOK_PANEL_OPEN)
	look.state(panel_open(src) ? "fab-o" : "fab-idle")
	look.overlay("fab-active", when = !!being_built)

/// A shared definition/flyweight (never cleared).
/obj/machinery/mecha_part_fabricator_tg/proc/stored_research() as /datum/techweb
	return stored_research_static

/// the being_built this refers to (a relation view: null once it is deleted).
/obj/machinery/mecha_part_fabricator_tg/proc/being_built() as /datum/design_techweb
	return being_built
