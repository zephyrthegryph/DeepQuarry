// The autolathe (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list says what it is: a machine built from a board (behind the open panel a crowbar takes it apart: board_machine()), a
// screwdriver panel with the lathe's wires behind it (the hack and the disable wires, a shock wire), a part-replacer target, a fabricator that prints
// its designs from its own materials (fabricator(): the print run, its refusals, where prints drop, examine), a disk drive that teaches it designs,
// its window, and a touch that shocks while its shock wire is live. Nothing of it works while it prints but the window and the run itself. The
// imperative parts below are its own: which designs it knows, how long one takes, the window's data, the disk's import and the look.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits (BROKEN, NOPOWER, ...) read through machine_basics()'s one
// bridge contribution, RefreshParts() with the circuit board and its parts, and dismantle() (the frame, the board and the parts).

MSG_DEF_SELF(autolathe/voltage, "Unable to print, voltage mismatch in internal wiring.")
MSG_DEF(autolathe/uploading, "You begin to upload %I% into %T%.", "%U% begins to load %I% in %T%...")

/obj/machinery/autolathe
	name = "autolathe"
	desc = "It produces items using steel, glass, plastic and maybe some more."
	icon_state = "autolathe"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 2000
	clicksound = SFX_KEYBOARD
	clickvol = 30

	circuit = /obj/item/circuitboard/autolathe

	/// A map's word that the lathe starts hacked: its hack wire starts cut (mending it unhacks the lathe).
	var/hacked_at_start = FALSE
	///Coefficient applied to consumed materials. Lower values result in lower material consumption.
	var/creation_efficiency = 1
	///modifier for lathe build speed. Lower values are faster.
	var/lathe_build_rate = 0.8
	///Designs related to the autolathe
	var/datum/techweb/autounlocking/stored_research_static
	///Designs imported from technology disks that we can print.
	var/list/imported_designs
	///The container to hold materials
	var/datum/material_container/materials
	///direction we output onto (if 0, on top of us)
	var/drop_direction = 0
	//looping sound for printing items
	var/datum/looping_sound/lathe_print/print_sound
	/// The print run under way (fabricator()), owned while it runs.
	var/datum/fab_run/print_run

/// The hacked designs are unlocked: the hack wire cut, or for five seconds after a pulse (lathe_wires()).
STAT(/obj/machinery/autolathe, hacked, ANY)
/// The lathe will not print: the disable wire cut, or for five seconds after a pulse (lathe_wires()).
STAT(/obj/machinery/autolathe, disabled, ANY)
/// The lathe shocks whoever touches it: the shock wire cut, or for five seconds after a pulse (shock_wire()).
STAT(/obj/machinery/autolathe, shocked, ANY)

CAPABILITIES(/obj/machinery/autolathe)
	machine_basics(repair = NONE, frame = board_machine())
	owns_one(nameof(materials), /datum/material_container, starts = PROC_REF(make_materials))
	owns_one(nameof(print_sound), /datum/looping_sound/lathe_print, starts = PROC_REF(make_print_sound))
	owns_one(nameof(print_run), /datum/fab_run)
	panel()
	// the panel opens at once, not while it prints, and shows whoever opened it the wires
	extend("panel.open", wait(0), needs(req_is(FABRICATOR_PRINTING, FALSE, because = MSG(fabricator/busy))))
	extend("panel.open", then(PROC_REF(panel_toggled)))
	wires(name = "Autolathe", count = 6, by_hand = TRUE, status_lines = PROC_REF(wire_lights), starts_cut = PROC_REF(wires_cut_at_start))
	lathe_wires(pulse_lasts = 5 SECONDS, refresh = TRUE)
	shock_wire(stat = STAT_SHOCKED, pulse_lasts = 5 SECONDS)
	on_change(nameof(hacked), EXIT, then(PROC_REF(hack_ran_out)))
	part_replacement()
	extend("part_replacement.replace", needs(req_is(FABRICATOR_PRINTING, FALSE, because = MSG(fabricator/busy))))
	fabricator(buildtypes = AUTOLATHE, efficiency = nameof(creation_efficiency), action = "make", design_arg = "id", count_arg = "multiplier",
		knows = PROC_REF(knows_design), build_time = PROC_REF(design_build_time), worth_floor = 5)
	extend("fabricator.print", needs(req_is(STAT_DISABLED, FALSE, because = MSG(autolathe/voltage))))
	// a design or tech disk teaches it what it can make of the disk's designs
	op("load_disk", item(/obj/item/disk), label("Upload designs"), when(req(list(/obj/item/disk/design_disk, /obj/item/disk/tech_disk))),
		needs(req_closed(SPACE_PANEL), req_operable(), req_is(FABRICATOR_PRINTING, FALSE, because = MSG(fabricator/busy))),
		wait(1.5 SECONDS), begins(MSG(autolathe/uploading)), then(PROC_REF(disk_loaded)))
	// a live shock wire shocks the hand that touches the shut lathe, in place of its window
	op("touch", hand(), label("Touch"), priority(OP_PRIORITY_NORMAL + 1), when(PROC_REF(touch_shocks)), then(PROC_REF(toucher_shocked)))

	section(window, "The window: its designs, its materials and the print button (fabricator())")
	interface("Autolathe")
	ui_shape(materialtotal = num(), materialsmax = num(), active = bool(), materials = list_of(row()), materialChoices = list_of(row()))
	extend("ui_open", needs(req_is(STAT_DISABLED, FALSE, because = MSG(autolathe/voltage))))
	extend(TAG_UI, needs(req_is(STAT_DISABLED, FALSE, because = MSG(autolathe/voltage))))

/obj/machinery/autolathe/Initialize(mapload)
	. = ..()
	stored_research_static = SSresearch.autounlock_techweb(/datum/techweb/autounlocking/autolathe)
	default_apply_parts()
	RefreshParts()

/// Its material store: every material, listed on examine; a sheet put in plays the loading animation.
/obj/machinery/autolathe/proc/make_materials(current)
	return new /datum/material_container(src, subtypesof(/datum/material), 0, MATCONTAINER_EXAMINE, \
		container_events = list((/datum/notice/matcontainer_item_consumed) = TYPE_PROC_REF(/obj/machinery/autolathe, material_inserted)))

/obj/machinery/autolathe/proc/make_print_sound(current)
	return new /datum/looping_sound/lathe_print(list(src), FALSE, TRUE)

/obj/machinery/autolathe/proc/material_inserted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	flick("autolathe_loading", src)//plays metal insertion animation

/obj/machinery/autolathe/RefreshParts()
	. = ..()
	var/mat_capacity = get_part_rating(/obj/item/stock_parts/matter_bin) * (37.5*SHEET_MATERIAL_AMOUNT)
	materials.max_amount = mat_capacity

	var/man_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	creation_efficiency = max(0.6, round(1.1 - (man_rating * 0.1), 0.1)) // creation_efficiency goes 1 -> 0.9 -> 0.8 -> 0.7 -> 0.6 per level of manipulator efficiency
	lathe_build_rate = 0.85 - (man_rating * 0.05) // lathe_build_rate goes 0.8 -> 0.75 -> 0.7 -> 0.65 -> 0.6 per level of manipulator efficiency

/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/obj/machinery/autolathe/proc/stored_research() as /datum/techweb/autounlocking
	return stored_research_static

// ---- the fabricator's questions ----

/// It knows a design it was built with or a disk taught it; a hacked design only while hacked; never a reagent.
/obj/machinery/autolathe/proc/knows_design(datum/design_techweb/D)
	if(D.make_reagent)
		return FALSE
	if(!LAZYACCESS(stored_research().researched_designs, D.id) && !LAZYACCESS(imported_designs, D.id))
		return FALSE
	return hacked || !(RND_CATEGORY_HACKED in D.category)

/// One item of `D` takes this long: faster with better manipulators.
/obj/machinery/autolathe/proc/design_build_time(datum/design_techweb/D)
	return (D.construction_time * D.lathe_time_factor) ** lathe_build_rate

// ---- the window ----

/// The designs it offers (the hacked ones only while hacked).
/obj/machinery/autolathe/proc/handle_designs(list/designs)
	PRIVATE_PROC(TRUE)
	. = list()
	for(var/design_id in designs)
		var/datum/design_techweb/design = SSresearch.techweb_design_by_id(design_id)
		if(!design || !knows_design(design))
			continue
		. += list(fabricator_design_row(design, creation_efficiency))

/obj/machinery/autolathe/tgui_static_data(mob/user)
	var/list/data = materials.tgui_static_data()
	data["designs"] = handle_designs(stored_research().researched_designs)
	data["designs"] += handle_designs(imported_designs)
	return data

/obj/machinery/autolathe/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/sheetmaterials),
		get_asset_datum(/datum/asset/spritesheet_batched/research_designs),
	)

/obj/machinery/autolathe/ui_data(datum/act/eval/A)
	return list(
		"materialtotal" = materials.total_amount(),
		"materialsmax" = materials.max_amount,
		"active" = !!fabricator_printing(src),
		"materials" = materials.material_list_data(),
		"materialChoices" = lathe_material_choice_list(materials),
	)

/// The hacked designs went (a hack pulse ran out): the window of whoever pulsed the wire shows it.
/obj/machinery/autolathe/proc/hack_ran_out(datum/act/A)
	update_tgui_static_data(wires_last_user(src))

// ---- the panel, the touch and the disk ----

/// The panel was opened: whoever opened it sees the wires.
/obj/machinery/autolathe/proc/panel_toggled(datum/act/op/A)
	if(panel_open(src))
		wires_open(src, A.actor)

/// A live shock wire on a shut, working lathe shocks the hand that touches it.
/obj/machinery/autolathe/proc/touch_shocks(datum/act/A)
	return shocked && !panel_open(src) && operable()

/obj/machinery/autolathe/proc/toucher_shocked(datum/act/op/A)
	shock(A.actor, 50)
	return OP_OK

/// The disk's designs this lathe can make, and does not know yet, are added; the others are named.
/obj/machinery/autolathe/proc/disk_loaded(datum/act/op/A)
	var/mob/user = A.actor
	var/list/not_imported
	var/design_count = 0
	if(istype(A.held, /obj/item/disk/design_disk))
		var/obj/item/disk/design_disk/disky = A.held
		for(var/datum/design_techweb/blueprint as anything in disky.blueprints)
			if(!blueprint || LAZYACCESS(imported_designs, blueprint.id) || LAZYACCESS(stored_research().researched_designs, blueprint.id))
				continue
			if(blueprint.build_type & AUTOLATHE)
				LAZYSET(imported_designs, blueprint.id, TRUE)
				design_count++
			else
				LAZYADD(not_imported, blueprint.name)
	else if(istype(A.held, /obj/item/disk/tech_disk))
		var/obj/item/disk/tech_disk/disky = A.held
		var/datum/techweb/disk_web = disky.stored_research()
		for(var/design_id in disk_web.researched_designs)
			var/datum/design_techweb/blueprint = SSresearch.techweb_design_by_id(design_id)
			if(!blueprint || LAZYACCESS(imported_designs, blueprint.id) || LAZYACCESS(stored_research().researched_designs, blueprint.id))
				continue
			// failed designs are not named: a tech disk can hold a whole web
			if(blueprint.build_type & AUTOLATHE)
				LAZYSET(imported_designs, blueprint.id, TRUE)
				design_count++
	if(design_count)
		to_chat(user, span_notice("[design_count] design\s imported."))
	if(not_imported)
		to_chat(user, span_warning("The following design[length(not_imported) > 1 ? "s" : ""] couldn't be imported: [english_list(not_imported)]"))
	update_static_data_for_all_viewers()
	return OP_OK

// ---- the look ----

/// It works while it prints; its open panel shows over it.
/obj/machinery/autolathe/draw(datum/look/look)
	..()
	look.hide(LOOK_PANEL_OPEN)
	look.state(fabricator_printing(src) && !power_lost() ? "autolathe_n" : initial(icon_state))
	look.overlay("autolathe_panel", when = panel_open(src))

// ---- the wires ----

/// A lathe mapped hacked starts with its hack wire cut.
/obj/machinery/autolathe/proc/wires_cut_at_start()
	return hacked_at_start ? list(WIRE_LATHE_HACK) : null

/obj/machinery/autolathe/proc/wire_lights()
	return list(
		"The red light is [disabled ? "off" : "on"].",
		"The green light is [shocked ? "off" : "on"].",
		"The blue light is [hacked ? "off" : "on"].")
