/obj/machinery/rnd/production
	name = "technology fabricator"
	desc = "Makes researched and prototype items with materials and energy."
	/// Energy cost per full stack of materials spent. Material insertion is 40% of this.
	active_power_usage = 5000
	// interaction_flags_atom = parent_type::interaction_flags_atom | INTERACT_ATOM_MOUSEDROP_IGNORE_CHECKS

	/// The efficiency coefficient. Material costs and print times are multiplied by this number;
	var/efficiency_coeff = 1
	/// The material storage used by this fabricator.
	var/datum/remote_materials/materials
	/// Which departments are allowed to process this design
	var/allowed_department_flags = ALL
	/// Icon state when production has started
	var/production_animation
	/// The types of designs this fabricator can print.
	var/allowed_buildtypes = NONE
	/// All designs in the techweb that can be fabricated by this machine, since the last update.
	var/list/datum/design_techweb/available_designs
	/// What color is this machine's stripe? Leave null to not have a stripe.
	var/stripe_color = null
	///direction we output onto (if 0, on top of us)
	var/drop_direction = 0
	///looping sound for printing items
	var/datum/looping_sound/lathe_print/print_sound
	///coalesces on_techweb_update() bursts: only the first update schedules the refresh
	var/techweb_updating = FALSE
	/// Personal account credited for the current print run's production bonus.
	var/current_producer_account = 0
	/// The current print run (start_making()): design, items left, time and power per item,
	/// material cost coefficient and the chosen materials.
	var/datum/design_techweb/build_design
	var/build_remaining = 0
	var/build_time_per_item = 1 SECOND
	var/build_charge_per_item = 0
	var/build_coefficient = 1
	var/tmp/list/build_chosen_materials

/// One item every build_time_per_item while busy printing.
DECLARE_REPEAT(/obj/machinery/rnd/production, "build_time_per_item", do_make_item, "busy")


/obj/machinery/rnd/production/Initialize(mapload)
	own_set(src, nameof(print_sound), new /datum/looping_sound/lathe_print(list(src), FALSE))
	own_set(src, nameof(materials), new /datum/remote_materials(
		src, \
		mapload, \
		mat_container_events = list( \
			(/datum/om/event/matcontainer_item_consumed) = TYPE_PROC_REF(/obj/machinery/rnd/production, local_material_insert)
		) \
	))

	available_designs = list()

	. = ..()

	default_apply_parts()
	RefreshParts()
	update_icon()


DECLARE_APPEARANCE_PROC(/obj/machinery/rnd/production, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/rnd/production/appearance_overlays()
	. = list()

	icon_state = "[initial(icon_state)][panel_open ? "_t" : ""]"

	if(!stripe_color)
		return .

	var/mutable_appearance/stripe = mutable_appearance('icons/obj/machines/research_vr.dmi', "protolathe_stripe[panel_open ? "_t" : ""]")
	stripe.color = stripe_color
	. += stripe

/obj/machinery/rnd/production/examine(mob/user, infix, suffix)
	. = ..()

	if(!in_range(user, src) && !isobserver(user))
		return

	. += span_notice("Material usage cost at <b>[efficiency_coeff * 100]%</b>")
	. += span_notice("Build time at <b>[efficiency_coeff * 100]%</b>")
	if(drop_direction)
		. += span_notice("Currently configured to drop printed objects <b>[dir2text(drop_direction)]</b>.")
		. += span_notice("Alt-click to reset.")
	else
		. += span_notice("Drag towards a direction (while next to it) to change drop direction.")

/obj/machinery/rnd/production/connect_techweb(datum/techweb/new_techweb)
	if(stored_research)
		om_unhook(stored_research, list(/datum/om/event/techweb_add_design, /datum/om/event/techweb_remove_design), src)
	return ..()

/obj/machinery/rnd/production/on_connected_techweb()
	. = ..()
	om_hook(stored_research, list(/datum/om/event/techweb_add_design, /datum/om/event/techweb_remove_design), src, TYPE_PROC_REF(/obj/machinery/rnd/production, on_techweb_update))
	update_designs()

/// Updates the list of designs this fabricator can print.
/obj/machinery/rnd/production/proc/update_designs()
	PROTECTED_PROC(TRUE)
	techweb_updating = FALSE

	var/previous_design_count = available_designs.len

	available_designs.Cut()

	for(var/design_id in stored_research.researched_designs)
		var/datum/design_techweb/design = GLOB.research_service.techweb_design_by_id(design_id)

		// TODO: only enable this if we port departmental techfabs
		// if((isnull(allowed_department_flags) || (design.departmental_flags & allowed_department_flags)) && (design.build_type & allowed_buildtypes))
		if(design.build_type & allowed_buildtypes)
			available_designs |= design

	var/design_delta = available_designs.len - previous_design_count

	if(design_delta > 0)
		atom_say("Received [design_delta] new design[design_delta == 1 ? "" : "s"].")
		play_sfx(src, SFX_MACHINES_TWOBEEP)

	update_static_data_for_all_viewers()

/obj/machinery/rnd/production/proc/on_techweb_update(datum/source, datum/om/event/event)
	EVENT_HANDLER

	if(!techweb_updating) //so we batch these updates together
		techweb_updating = TRUE
		om_after(src, 2 SECONDS, PROC_REF(update_designs))

/**
 * Consumes power for the item inserted either into silo or local storage.
 * Arguments
 *
 * * obj/item/item_inserted - the item to process
 * * list/mats_consumed - list of mats consumed
 * * amount_inserted - amount of material actually processed
 */
/obj/machinery/rnd/production/proc/process_item(obj/item/item_inserted, list/mats_consumed, amount_inserted)
	PRIVATE_PROC(TRUE)

	//we use initial(active_power_usage) because higher tier parts will have higher active usage but we have no benifit from it
	if(use_power_oneoff(ROUND_UP((amount_inserted / (MAX_STACK_SIZE * SHEET_MATERIAL_AMOUNT)) * 0.4 * initial(active_power_usage))))
		var/datum/material/highest_mat_ref

		var/highest_mat = 0
		for(var/datum/material/mat as anything in mats_consumed)
			var/present_mat = mats_consumed[mat]
			if(present_mat > highest_mat)
				highest_mat = present_mat
				highest_mat_ref = mat

		flick_animation(highest_mat_ref)
/**
 * Plays an visual animation when materials are inserted
 * Arguments
 *
 * * mat - the material ref we are trying to animate on the machine
 */
/obj/machinery/rnd/production/proc/flick_animation(datum/material/mat_ref)
	PROTECTED_PROC(TRUE)
	SHOULD_CALL_PARENT(FALSE)

	//first play the insertion animation
	flick_overlay_view_atom(material_insertion_animation(mat_ref), 1 SECONDS)

	//now play the progress bar animation
	flick_overlay_view_atom(mutable_appearance('icons/obj/machines/research_vr.dmi', "protolathe_progress"), 1 SECONDS)

///When materials are instered into local storage
/obj/machinery/rnd/production/proc/local_material_insert(datum/source, datum/om/event/matcontainer_item_consumed/event)
	EVENT_HANDLER

	process_item(event.item, event.mats_consumed, event.material_amount)

/obj/machinery/rnd/production/RefreshParts()
	. = ..()

	var/total_storage = get_part_rating(/obj/item/stock_parts/matter_bin) * 37.5 * SHEET_MATERIAL_AMOUNT
	materials.set_local_size(total_storage)

	efficiency_coeff = compute_efficiency()

	update_static_data_for_all_viewers()

///Computes this machines cost efficiency based on the available parts
/obj/machinery/rnd/production/proc/compute_efficiency()
	PROTECTED_PROC(TRUE)

	var/efficiency = 1.2 - get_part_rating(/obj/item/stock_parts/manipulator) * 0.1

	return efficiency

/**
 * The cost efficiency for an particular design
 * Arguments
 *
 * * path - the design path to check for
 */
/obj/machinery/rnd/production/proc/build_efficiency(path)
	PRIVATE_PROC(TRUE)
	SHOULD_BE_PURE(TRUE)

	if(ispath(path, /obj/item/stack))
		return 1
	else
		return efficiency_coeff

/obj/machinery/rnd/production/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/sheetmaterials),
		get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	)

DECLARE_UI(/obj/machinery/rnd/production, "Fabricator")

/obj/machinery/rnd/production/tgui_static_data(mob/user)
	var/list/data = ..()

	var/list/designs = list()

	var/datum/asset/spritesheet_batched/research_designs/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	var/size32x32 = "[spritesheet.name]32x32"

	var/coefficient
	for(var/datum/design_techweb/design in available_designs)
		if(!(isnull(allowed_department_flags) || (design.departmental_flags & allowed_department_flags)))
			continue
		if(!hacked && (RND_CATEGORY_HACKED in design.category))
			continue

		var/cost = list()

		coefficient = build_efficiency(design.build_path)
		for(var/mat_id in design.materials)
			cost[mat_id] = OPTIMAL_COST(design.materials[mat_id] * coefficient)

		var/css_id = sanitize_css_class_name(design.id)
		var/size = spritesheet.icon_size_id(css_id)
		designs[design.id] = list(
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

	data["designs"] = designs
	data["fabName"] = name

	var/list/material_data = materials.mat_container()?.tgui_static_data(user)
	if(material_data)
		data += material_data

	return data

UI_DATA_REPLACE(/obj/machinery/rnd/production, "busy:num", "merge:ui_data_obj_machinery_rnd_production{materials:list,materialChoices:unknown,onHold:bool,materialMaximum:unknown,queue:list}")

/// The computed part of /obj/machinery/rnd/production's window data (declared on its UI_DATA row).
/obj/machinery/rnd/production/proc/ui_data_obj_machinery_rnd_production(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/material_data = materials.mat_container()?.material_list_data(user)
	if(material_data)
		data["materials"] = material_data
	// Loaded materials offered in the per-design material picker (selectable designs).
	data["materialChoices"] = material_choice_list()
	data["onHold"] = FALSE //materials.on_hold()
	data["materialMaximum"] = materials.local_size
	data["queue"] = list()

	return data

/obj/machinery/rnd/production/proc/material_choice_list()
	return lathe_material_choice_list(materials?.mat_container())

// Shared: loaded materials (>= 1 sheet) offered in a lathe's per-design material
// picker. Used by both the protolathe family and the autolathe.
/proc/lathe_material_choice_list(datum/material_container/cont)
	var/list/out = list()
	if(!istype(cont))
		return out
	for(var/datum/material/mat as anything in cont.materials)
		var/amount = cont.materials[mat]
		if(amount < SHEET_MATERIAL_AMOUNT)
			continue
		out += list(material_choice_tgui(mat, amount))
	return out

/// One canonical material presentation for lathes and hand crafting.
/proc/material_choice_tgui(datum/material/mat, amount)
	return list(
			"id" = mat.name,
			"label" = mat.display_name || mat.name,
			"sheets" = round(amount / SHEET_MATERIAL_AMOUNT),
			"color" = mat.icon_colour || "#aaaaaa",
			"layers" = list(),
			"responses" = mat.material_response_summary(),
			"hardness" = round(mat.hardness),
			"density" = round(mat.density),
			"integrity" = round(mat.integrity),
			"elasticity" = round(mat.elasticity),
			"brittleness" = round(mat.brittleness),
			"toughness" = round(mat.fracture_toughness),
			"conductivity" = round(mat.conductivity),
			"heatResistance" = round(mat.heat_resistance),
			"thermalInsulation" = round(mat.thermal_insulation),
			"corrosionResistance" = round(mat.corrosion_resistance),
			"pressureLimit" = round(mat.material_pressure_limit(MATERIAL_PIPE_REFERENCE_RADIUS, MATERIAL_PIPE_REFERENCE_THICKNESS, T20C) / ONE_ATMOSPHERE, 0.1),
			"resistivity" = mat.electrical_resistivity,
			"criticalTemperature" = mat.critical_temperature,
			"criticalCurrentDensity" = mat.critical_current_density,
			"specificHeat" = mat.specific_heat,
			"phaseCapacity" = mat.phase_change_capacity,
			"phaseTemperature" = mat.phase_change_temperature,
			"dielectricStrength" = mat.dielectric_strength,
			"meltingPoint" = mat.melting_point,
		)

UI_ACT(/obj/machinery/rnd/production, "remove_mat", ui_act_remove_mat, UI_ARG_NUM("amount"), UI_ARG_TEXT("id", 64))
UI_ACT_PROC(/obj/machinery/rnd/production, ui_act_remove_mat)
	var/datum/material/material = GLOB.name_to_material[params["id"]]
	if(!istype(material))
		return

	var/amount = params["amount"]
	if(isnull(amount))
		return

	//we use initial(active_power_usage) because higher tier parts will have higher active usage but we have no benifit from it
	if(!use_power_oneoff(ROUND_UP((amount / MAX_STACK_SIZE) * 0.4 * initial(active_power_usage))))
		atom_say("No power to dispense sheets")
		return

	materials.eject_sheets(material, amount)
	return TRUE

UI_ACT(/obj/machinery/rnd/production, "build", ui_act_build, UI_ARG_NUM("amount", 1, 50), UI_ARG_LIST("materialSlots"), UI_ARG_TEXT("ref", 256))
UI_ACT_PROC(/obj/machinery/rnd/production, ui_act_build)
	if(busy)
		atom_say("Warning: fabricator is busy!")
		return

	//validate design
	var/design_id = params["ref"]
	if(!design_id)
		return
	var/datum/design_techweb/design = LAZYACCESS(stored_research.researched_designs, design_id) ? GLOB.research_service.techweb_design_by_id(design_id) : null
	if(!istype(design))
		return FALSE
	if(!(isnull(allowed_department_flags) || (design.departmental_flags & allowed_department_flags)))
		atom_say("This fabricator does not have the necessary keys to decrypt this design.")
		return FALSE
	if(design.build_type && !(design.build_type & allowed_buildtypes))
		atom_say("This fabricator does not have the necessary manipulation systems for this design.")
		return FALSE

	//validate print quantity
	var/print_quantity = params["amount"]
	if(isnull(print_quantity))
		return

	// Material-selectable designs let the user pick which loaded material to use.
	var/list/chosen_materials = params["materialSlots"] || list()
	if(design.material_template && !design.material_choice_valid(chosen_materials))
		atom_say("Select valid materials for every required construction slot.")
		return FALSE
	var/list/effective_mats = design.effective_materials(chosen_materials)

	//efficiency for this design, stacks use exact materials
	var/coefficient = build_efficiency(design.build_path)

	//check for materials
	if(!materials.can_use_resource())
		return
	if(!materials.mat_container().has_materials(effective_mats, coefficient, print_quantity))
		atom_say("Not enough materials to complete prototype[print_quantity > 1 ? "s" : ""].")
		return FALSE

	//compute power & time to print 1 item
	var/charge_per_item = 0
	for(var/material in effective_mats)
		charge_per_item += effective_mats[material]
	charge_per_item = ROUND_UP((charge_per_item / (MAX_STACK_SIZE * SHEET_MATERIAL_AMOUNT)) * coefficient * active_power_usage)
	var/build_time_per_item = (design.construction_time * design.lathe_time_factor * efficiency_coeff) ** 0.8

	//start production
	var/obj/item/card/id/producer_id = ui.user.GetIdCard()
	current_producer_account = producer_id?.associated_account_number || 0
	shared_set(src, nameof(/obj/machinery/rnd/production::build_design), design)
	build_remaining = print_quantity
	src.build_time_per_item = build_time_per_item
	build_coefficient = coefficient
	build_charge_per_item = charge_per_item
	build_chosen_materials = chosen_materials
	set_busy(TRUE)
	SStgui.update_uis(src)
	print_sound.start()
	if(production_animation)
		icon_state = production_animation

	return TRUE

/// Where printed items drop: the tile in drop_direction (unless it is a wall), else our own.
/obj/machinery/rnd/production/proc/production_drop_target()
	if(drop_direction)
		var/turf/target_location = get_step(src, drop_direction)
		if(!iswall(target_location))
			return target_location
	return get_turf(src)

/**
 * One step of the print run (DECLARE_REPEAT while busy): makes the next item of build_design
 * (build_remaining left, build_time_per_item apart, build_charge_per_item power each, cost
 * scaled by build_coefficient) and drops it on production_drop_target().
*/
/obj/machinery/rnd/production/proc/do_make_item()
	PROTECTED_PROC(TRUE)
	var/datum/design_techweb/design = build_design
	var/items_remaining = build_remaining
	var/material_cost_coefficient = build_coefficient
	var/charge_per_item = build_charge_per_item
	var/list/chosen_materials = build_chosen_materials
	var/turf/target = production_drop_target()

	if(!items_remaining || !design) // how
		finalize_build()
		return REPEAT_STOP

	if(has_stat(NOPOWER))
		atom_say("Unable to continue production, power failure.")
		finalize_build()
		return REPEAT_STOP

	if(!use_power_oneoff(charge_per_item)) // provide the wait time until lathe is ready
		var/area/my_area = get_area(src)
		var/obj/machinery/power/apc/my_apc = my_area.apc
		if(!QDELETED(my_apc))
			atom_say("Unable to continue production, APC overload.")
		else
			atom_say("Unable to continue production, no APC in area.")
		finalize_build()
		return REPEAT_STOP

	if(!materials.can_use_resource())
		atom_say("Unable to continue production, materials on hold.")
		finalize_build()
		return REPEAT_STOP

	var/is_stack = ispath(design.build_path, /obj/item/stack)
	var/list/design_materials = design.effective_materials(chosen_materials)
	if(!materials.mat_container().has_materials(design_materials, material_cost_coefficient, is_stack ? items_remaining : 1))
		atom_say("Unable to continue production, missing materials.")
		finalize_build()
		return REPEAT_STOP
	materials.use_materials(design_materials, material_cost_coefficient, is_stack ? items_remaining : 1, "built", "[design.name]")

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
				created_stack.set_economic_provenance(DEPARTMENT_RESEARCH, max(10, build_time_per_item / 10), current_producer_account)
			created.forceMove(target)
			number_to_make -= max_stack_amount

		created = new stack_item(null, number_to_make)
	else
		created = design.create_item(null, chosen_materials)
		split_materials_uniformly(design_materials, material_cost_coefficient, created)

	if(isitem(created))
		created.pixel_x = rand(-6, 6)
		created.pixel_y = rand(-6, 6)
		var/obj/created_object = created
		created_object.set_economic_provenance(DEPARTMENT_RESEARCH, max(10, build_time_per_item / 10), current_producer_account)
	created.forceMove(target)

	if(is_stack)
		items_remaining = 0
	else
		items_remaining -= 1

	build_remaining = items_remaining
	if(!items_remaining)
		finalize_build()
		return REPEAT_STOP

/// Resets the busy flag
/// Called at the end of do_make_item's timer loop
/obj/machinery/rnd/production/proc/finalize_build()
	PROTECTED_PROC(TRUE)
	print_sound.stop()
	set_busy(FALSE)
	shared_set(src, nameof(build_design), null)
	build_chosen_materials = null
	current_producer_account = 0
	SStgui.update_uis(src)
	icon_state = initial(icon_state)

/obj/machinery/rnd/production/MouseDrop(atom/over, src_location, over_location, src_control, over_control, params)
	var/mob/user = usr
	if(!Adjacent(user))
		return
	if(isobserver(user) || user.is_incorporeal())
		return
	if(busy)
		balloon_alert(user, "busy printing!")
		return
	var/direction = get_dir(src, over_location)
	if(!direction)
		return
	drop_direction = direction
	balloon_alert(user, "dropping [dir2text(drop_direction)]")
