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
	maintenance_flags = MACHINE_MAINT_STANDARD

	circuit = /obj/item/circuitboard/autolathe

	var/static/datum/category_collection/autolathe/autolathe_recipes

	///Is the autolathe hacked via wiring
	var/hacked = FALSE
	///Is the autolathe disabled via wiring
	var/disabled = FALSE
	///Did we recently shock a mob who medled with the wiring
	var/shocked = FALSE
	///Are we currently printing something
	/// Personal account credited for the current print run's production bonus.
	var/current_producer_account = 0
	var/current_producer_department

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

/obj/machinery/autolathe/Initialize(mapload)
	print_sound = new(list(src), FALSE, TRUE)
	materials = new /datum/material_container( \
		src, \
		subtypesof(/datum/material), \
		0, \
		MATCONTAINER_EXAMINE, \
		container_events = list((/datum/om/event/matcontainer_item_consumed) = TYPE_PROC_REF(/obj/machinery/autolathe, AfterMaterialInsert)) \
	)
	. = ..()

	set_wires(new /datum/wires/autolathe(src))

	if(!GLOB.autounlock_techwebs[/datum/techweb/autounlocking/autolathe])
		GLOB.autounlock_techwebs[/datum/techweb/autounlocking/autolathe] = new /datum/techweb/autounlocking/autolathe
	stored_research_static = GLOB.autounlock_techwebs[/datum/techweb/autounlocking/autolathe]

	default_apply_parts()
	RefreshParts()

DECLARE_REF(/obj/machinery/autolathe, "print_sound", OWNED, null)
DECLARE_REF(/obj/machinery/autolathe, "materials", OWNED, null)

/obj/machinery/autolathe/examine(mob/user)
	. = ..()
	if(!in_range(user, src) && !isobserver(user))
		return
	. += span_notice("Material usage cost at <b>[creation_efficiency * 100]%</b>.")
	if(drop_direction)
		. += span_notice("Currently configured to drop printed objects <b>[dir2text(drop_direction)]</b>.")
		. += span_notice("Alt-click to reset.")
	else
		. += span_notice("Drag towards a direction (while next to it) to change drop direction.")
	. += span_notice("Its maintenance panel is [!panel_open ? "closed" : "open"].")

/obj/machinery/autolathe/crowbar_act(mob/living/user, obj/item/tool)
	return ..()

/obj/machinery/autolathe/screwdriver_act(mob/living/user, obj/item/tool)
	if(om_busy(src))
		return ITEM_INTERACT_BLOCKING
	. = ..()
	if(. == ITEM_INTERACT_SUCCESS)
		interact(user)

/obj/machinery/autolathe/wirecutter_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/autolathe/multitool_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/autolathe/tgui_status(mob/user)
	if(disabled)
		return STATUS_CLOSE
	return ..()

/obj/machinery/autolathe/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/autolathe_interact,
		/datum/interaction/machine_alt/autolathe_reset_drop,
		/datum/interaction/machine_item/autolathe_attackby,
	)
	..()

/// Old attack_hand: `interact(user)`, never called ..().
/datum/interaction/machine_hand/ungated/autolathe_interact
	id = "autolathe_interact"
	name = "Use"
	effect = /obj/machinery/autolathe/proc/interaction_use

/obj/machinery/autolathe/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	interact(user)
	return TRUE

/obj/machinery/autolathe/interact(mob/user)
	if(panel_open)
		return wires.Interact(user)

	if(has_stat(NOPOWER | EMPED))
		return

	if(shocked && !has_stat(NOPOWER))
		shock(user, 50)
		return

	tgui_interact(user)

/obj/machinery/autolathe/proc/AfterMaterialInsert(datum/source, datum/om/event/matcontainer_item_consumed/event)
	EVENT_HANDLER
	flick("autolathe_loading", src)//plays metal insertion animation
	SStgui.update_uis(src)

DECLARE_UI(/obj/machinery/autolathe, "Autolathe")

/**
 * Converts all the designs supported by this autolathe into UI data
 * Arguments
 *
 * * list/designs - the list of techweb designs we are trying to send to the UI
 */
/obj/machinery/autolathe/proc/handle_designs(list/designs)
	PRIVATE_PROC(TRUE)

	if(!length(designs))
		return list()

	var/list/output = list()

	var/datum/asset/spritesheet_batched/research_designs/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	var/size32x32 = "[spritesheet.name]32x32"

	for(var/design_id in designs)
		var/datum/design_techweb/design = GLOB.research_service.techweb_design_by_id(design_id)
		if(design.make_reagent)
			continue
		if(!hacked && (RND_CATEGORY_HACKED in design.category))
			continue

		//compute cost & maximum number of printable items
		var/coeff = (ispath(design.build_path, /obj/item/stack) ? 1 : creation_efficiency)
		var/list/cost = list()
		for(var/id in design.materials)
			var/datum/material/mat = get_material_by_name(id)
			cost[mat.name] = OPTIMAL_COST(design.materials[id] * coeff)

		//create & send ui data
		var/css_id = sanitize_css_class_name(design.id)
		var/size = spritesheet.icon_size_id(css_id)
		var/list/design_data = list(
			"name" = design.name,
			"desc" = design.get_description(),
			"cost" = cost,
			"id" = design.id,
			"categories" = design.category,
			"icon" = "[size == size32x32 ? "" : "[size] "][css_id]",
			"materialConfigurable" = !!design.material_template,
			"materialProfile" = design.material_application,
			"materialSlots" = material_slots_tgui(material_template_singleton(design.material_template), design.material_total),
		)

		output += list(design_data)

	return output

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

UI_DATA_REPLACE(/obj/machinery/autolathe, "merge:ui_data_obj_machinery_autolathe{materialtotal:unknown,materialsmax:num,active:unknown,materials:unknown,materialChoices:unknown}")

/// The computed part of /obj/machinery/autolathe's window data (declared on its UI_DATA row).
/obj/machinery/autolathe/proc/ui_data_obj_machinery_autolathe(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["materialtotal"] = materials.total_amount()
	data["materialsmax"] = materials.max_amount
	data["active"] = om_busy(src)
	data["materials"] = materials.material_list_data()
	data["materialChoices"] = lathe_material_choice_list(materials)

	return data

UI_ACT(/obj/machinery/autolathe, "make", ui_act_make, UI_ARG_TEXT("id", 256), UI_ARG_NUM("multiplier", 1, 50), UI_ARG_LIST("materialSlots"))
UI_ACT_PROC(/obj/machinery/autolathe, ui_act_make)
	add_fingerprint(user)

	//sanity checks to start printing
	if(disabled)
		atom_say("Unable to print, voltage mismatch in internal wiring.")
		return

	if(om_busy(src))
		atom_say("The autolathe is busy. Please wait for completion of previous operation.")
		return

	//validate design
	var/design_id = params["id"]
	if(!design_id)
		return
	var/valid_design = LAZYACCESS(stored_research().researched_designs, design_id)
	valid_design ||= LAZYACCESS(imported_designs, design_id)
	if(!valid_design)
		return
	var/datum/design_techweb/design = GLOB.research_service.techweb_design_by_id(design_id)
	if(isnull(design))
		stack_trace("got passed an invalid design id: [design_id] and somehow made it past all checks")
		return
	if(!(design.build_type & AUTOLATHE))
		atom_say("This fabricator does not have the necessary keys to decrypt this design.")
		return

	//validate print quantity
	var/build_count = params["multiplier"]
	if(isnull(build_count))
		return

	// Material-selectable designs let the user pick which loaded material to use.
	var/list/chosen_materials = params["materialSlots"] || list()
	if(design.material_template && !design.material_choice_valid(chosen_materials))
		atom_say("Select valid materials for every required construction slot.")
		return
	var/list/effective_mats = design.effective_materials(chosen_materials)

	// Check for materials required. For custom material items decode their required materials
	var/list/materials_needed = list()
	for(var/id, amount_needed in effective_mats)
		var/datum/material = (id in GLOB.name_to_material) ? get_material_by_name(id) : id
		if(!istype(material, /datum/material))
			CRASH("Autolathe ui_act got passed an invalid material id: [material]")
		materials_needed[material] += amount_needed

	//checks for available materials
	var/material_cost_coefficient = ispath(design.build_path, /obj/item/stack) ? 1 : creation_efficiency
	if(!materials.has_materials(materials_needed, material_cost_coefficient, build_count))
		atom_say("Not enough materials to begin production.")
		return

	//compute power & time to print 1 item
	var/charge_per_item = 0
	for(var/material, amount in effective_mats)
		charge_per_item += amount

	charge_per_item = ROUND_UP((charge_per_item / (MAX_STACK_SIZE * SHEET_MATERIAL_AMOUNT)) * material_cost_coefficient * active_power_usage)
	var/build_time_per_item = (design.construction_time * (design.lathe_time_factor)) ** lathe_build_rate

	//do the printing sequentially
	var/obj/item/card/id/producer_id = user.GetIdCard()
	current_producer_account = producer_id?.associated_account_number || 0
	current_producer_department = department_for_mob(user) || DEPARTMENT_ENGINEERING
	icon_state = "autolathe_n"
	// play this after all checks passed individually for each item.
	print_sound.start()
	var/turf/target_location
	if(drop_direction)
		target_location = get_step(src, drop_direction)
		if(target_location.density)
			target_location = get_turf(src)
	else
		target_location = get_turf(src)

	// The print run is a task claiming the lathe: busy (om_busy()) until the last item or a stop.
	var/datum/om/task/run = om_task_start(/datum/om/task/lathe_print, src, null, receiver = src, design = design, remaining = build_count, build_time = build_time_per_item, cost_coefficient = material_cost_coefficient, charge = charge_per_item, materials = materials_needed, drop_turf = target_location, chosen = chosen_materials)
	if(!istype(run))
		print_sound.stop()
		icon_state = initial(icon_state)
		return FALSE
	SStgui.update_uis(src)
	return TRUE

/// An autolathe print run: one item every `build_time` until `remaining` runs out or a check fails.
/datum/om/task/lathe_print
	name = "lathe print"
	claims_actor = TRUE
	steps = list(/obj/machinery/autolathe/proc/print_step = 0)
	complete_proc = /obj/machinery/autolathe/proc/print_run_ended
	cancel_proc = /obj/machinery/autolathe/proc/print_run_ended
	var/datum/design_techweb/design
	var/remaining = 0
	var/build_time = 0
	var/cost_coefficient = 1
	var/charge = 0
	var/list/materials
	var/turf/drop_turf
	var/list/chosen
	var/started = FALSE

/obj/machinery/autolathe/proc/print_step(datum/om/task/lathe_print/T)
	if(!T.started)
		T.started = TRUE
		return STEP_REPEAT(T.build_time)
	var/remaining = do_make_item(T.design, T.remaining, T.build_time, T.cost_coefficient, T.charge, T.materials, T.drop_turf, T.chosen)
	if(remaining <= 0)
		return STEP_DONE
	T.remaining = remaining
	return STEP_REPEAT(T.build_time)

/obj/machinery/autolathe/proc/print_run_ended(datum/om/task/T)
	finalize_build()

/**
 * One step of the print run (print_step()): makes the item, returns how many are left (0: stop)
 * Arguments
 *
 * * datum/design/design - the design we are trying to print
 * * items_remaining - the number of designs left out to print
 * * build_time_per_item - the time taken to print 1 item
 * * material_cost_coefficient - the cost efficiency to print 1 design
 * * charge_per_item - the amount of power to print 1 item
 * * list/materials_needed - the list of materials to print 1 item
 * * turf/target - the location to drop the printed item on
*/
/obj/machinery/autolathe/proc/do_make_item(datum/design_techweb/design, items_remaining, build_time_per_item, material_cost_coefficient, charge_per_item, list/materials_needed, turf/target, list/chosen_materials)
	PROTECTED_PROC(TRUE)

	if(items_remaining <= 0) // how
		return 0

	if(has_stat(NOPOWER | EMPED))
		atom_say("Unable to continue production, power failure.")
		return 0

	if(!use_power_oneoff(charge_per_item)) // provide the wait time until lathe is ready
		var/area/my_area = get_area(src)
		var/obj/machinery/power/apc/my_apc = my_area.apc
		if(!QDELETED(my_apc))
			atom_say("Unable to continue production, power grid overload.")
		else
			atom_say("Unable to continue production, no APC in area.")
		return 0

	var/is_stack = ispath(design.build_path, /obj/item/stack)
	if(!materials.has_materials(materials_needed, material_cost_coefficient, is_stack ? items_remaining : 1))
		atom_say("Unable to continue production, missing materials.")
		return 0
	materials.use_materials(materials_needed, material_cost_coefficient, is_stack ? items_remaining : 1)

	var/atom/movable/created
	if(is_stack)
		var/obj/item/stack/stack_item = initial(design.build_path)
		var/max_stack_amount = initial(stack_item.max_amount)
		var/number_to_make = (initial(stack_item.amount) * items_remaining)
		while(number_to_make > max_stack_amount)
			created = new stack_item(null, max_stack_amount) //it's imporant to spawn things in nullspace, since obj's like stacks qdel when they enter a tile/merge with other stacks of the same type, resulting in runtimes.
			if(isitem(created))
				created.pixel_x = rand(-6, 6)
				created.pixel_y = rand(-6, 6)
				var/obj/created_stack = created
				created_stack.set_economic_provenance(current_producer_department, max(5, build_time_per_item / 10), current_producer_account)
			created.forceMove(target)
			number_to_make -= max_stack_amount

		created = new stack_item(target, number_to_make)
	else
		created = design.create_item(target, chosen_materials)
		split_materials_uniformly(materials_needed, material_cost_coefficient, created)

	if(isitem(created))
		created.pixel_x = rand(-6, 6)
		created.pixel_y = rand(-6, 6)
		var/obj/created_object = created
		created_object.set_economic_provenance(current_producer_department || DEPARTMENT_ENGINEERING, max(5, build_time_per_item / 10), current_producer_account)

	if(is_stack)
		items_remaining = 0
	else
		items_remaining -= 1

	return items_remaining

/**
 * Resets the icon state when the print run's task ends (print_run_ended())
*/
/obj/machinery/autolathe/proc/finalize_build()
	PROTECTED_PROC(TRUE)
	print_sound.stop()
	icon_state = initial(icon_state)
	current_producer_account = 0
	current_producer_department = null
	SStgui.update_uis(src)

/obj/machinery/autolathe/MouseDrop(over_object, src_location, over_location)
	if(isobserver(usr) || !Adjacent(usr))
		return
	if(om_busy(src))
		balloon_alert(usr, "printing started!")
		return
	var/direction = get_dir(src, over_location)
	if(!direction)
		return
	drop_direction = direction
	balloon_alert(usr, "dropping [dir2text(drop_direction)]")

/// Old click_alt: kept whole (BLOCKING and SUCCESS both consume the input; neither falls through).
/datum/interaction/machine_alt/autolathe_reset_drop
	id = "autolathe_reset_drop"
	name = "Reset drop direction"
	effect = /obj/machinery/autolathe/proc/interaction_reset_drop

/obj/machinery/autolathe/proc/interaction_reset_drop(mob/user, obj/item/held, datum/interaction/interaction)
	if(!drop_direction)
		return TRUE
	if(om_busy(src))
		balloon_alert(user, "busy printing!")
		return TRUE
	balloon_alert(user, "drop direction reset")
	drop_direction = 0
	return TRUE

/**
 * Old attackby, kept whole. The robot-module/busy/part-replacement/stat/panel_open guards
 * swallow ANY item (they ran before the disk istype check); a non-disk item that passes
 * them falls through (effect returns FALSE) exactly as the old `return ..()` did.
 */
/datum/interaction/machine_item/autolathe_attackby
	id = "autolathe_attackby"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/autolathe/proc/interaction_attackby

/obj/machinery/autolathe/proc/interaction_attackby(mob/user, obj/item/O, datum/interaction/interaction)
	if(is_robot_module(O))
		return TRUE

	if(om_busy(src))
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		return TRUE

	if(default_part_replacement(user, O))
		return TRUE

	if(has_stat(MACHINE_STAT_ANY))
		return TRUE

	if(panel_open)
		to_chat(user, "close the panel first!")
		return TRUE

	if(!istype(O, /obj/item/disk/design_disk) && !istype(O, /obj/item/disk/tech_disk))
		return FALSE

	// The rest has to do with loading from design disks
	user.visible_message(span_notice("[user] begins to load \the [O] in \the [src]..."),
		balloon_alert(user, "uploading design..."),
		span_hear("You hear the chatter of a floppy drive."))

	om_task_start(/datum/om/task/timed/autolathe_interaction_attackby, user, src, receiver = src, O = O, busy = src)
	return TRUE

/datum/om/task/timed/autolathe_interaction_attackby
	duration = 1.5 SECONDS
	complete_proc = /obj/machinery/autolathe/proc/interaction_attackby_timed_done
	cancel_proc = /obj/machinery/autolathe/proc/interaction_attackby_timed_failed
	var/obj/item/O

/obj/machinery/autolathe/proc/interaction_attackby_timed_done(datum/om/task/timed/autolathe_interaction_attackby/task)
	var/mob/user = task.actor
	var/obj/item/O = task.O

	var/list/not_imported
	var/design_count = 0
	// Basic design loot disks
	if(istype(O, /obj/item/disk/design_disk))
		var/obj/item/disk/design_disk/disky = O
		for(var/datum/design_techweb/blueprint as anything in disky.blueprints)
			if(!blueprint)
				continue
			if(LAZYACCESS(imported_designs, blueprint.id) || LAZYACCESS(stored_research().researched_designs, blueprint.id))
				continue
			if(blueprint.build_type & AUTOLATHE)
				LAZYSET(imported_designs, blueprint.id, TRUE)
				design_count++
			else
				LAZYADD(not_imported, blueprint.name)

	// More complex as it holds multiple nodes of research
	else if(istype(O, /obj/item/disk/tech_disk))
		var/obj/item/disk/tech_disk/disky = O
		var/datum/techweb/disk_web = disky.stored_research()
		for(var/design_id in disk_web.researched_designs)
			var/datum/design_techweb/blueprint = GLOB.research_service.techweb_design_by_id(design_id)
			if(LAZYACCESS(imported_designs, blueprint.id) || LAZYACCESS(stored_research().researched_designs, blueprint.id))
				continue
			if(blueprint.build_type & AUTOLATHE)
				LAZYSET(imported_designs, blueprint.id, TRUE)
				design_count++
			// Don't report failed designs here, techwebs can be huge and the message would be massive for something like the debug disk

	if(design_count)
		to_chat(user, span_notice("[design_count] design\s imported."))

	if(not_imported)
		to_chat(user, span_warning("The following design[length(not_imported) > 1 ? "s" : ""] couldn't be imported: [english_list(not_imported)]"))

	update_static_data_for_all_viewers()
	return TRUE

/obj/machinery/autolathe/proc/interaction_attackby_timed_failed(datum/om/task/timed/autolathe_interaction_attackby/task)
	var/mob/user = task.actor
	update_static_data_for_all_viewers()
	balloon_alert(user, "interrupted!")
	return TRUE

/obj/machinery/autolathe/RefreshParts()
	. = ..()
	var/mat_capacity = get_part_rating(/obj/item/stock_parts/matter_bin) * (37.5*SHEET_MATERIAL_AMOUNT)
	materials.max_amount = mat_capacity

	var/man_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	creation_efficiency = max(0.6, round(1.1 - (man_rating * 0.1), 0.1)) // creation_efficiency goes 1 -> 0.9 -> 0.8 -> 0.7 -> 0.6 per level of manipulator efficiency
	lathe_build_rate = 0.85 - (man_rating * 0.05) // lathe_build_rate goes 0.8 -> 0.75 -> 0.7 -> 0.65 -> 0.6 per level of manipulator efficiency

/obj/machinery/autolathe/update_icon()
	cut_overlays()

	icon_state = initial(icon_state)

	if(panel_open)
		add_overlay("[icon_state]_panel")
	if(has_stat(NOPOWER))
		return
	if(om_busy(src))
		icon_state = "[icon_state]_work"

/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/obj/machinery/autolathe/proc/stored_research() as /datum/techweb/autounlocking
	return stored_research_static
DECLARE_REF(/obj/machinery/autolathe, "stored_research_static", STATIC, null)
