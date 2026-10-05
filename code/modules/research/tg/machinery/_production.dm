// The R&D production machines: the protolathe, the circuit imprinter and the department protolathes (doc/rewrite/final_api.html section 16,
// doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list adds to the R&D base (rdmachines.dm) what a production machine is: a fabricator (fabricator(): the build button, its
// refusals, the run, where builds drop, the sheets button, examine) over its material store (its own, or an ore silo it links to), its window,
// and the techweb designs it follows. The imperative parts below are its own: which designs it knows and how long one takes, the window's data,
// the store's insertion animation and the look.

/obj/machinery/rnd/production
	name = "technology fabricator"
	desc = "Makes researched and prototype items with materials and energy."
	/// Energy cost per full stack of materials spent. Material insertion is 40% of this.
	active_power_usage = 5000

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
	/// The print run under way (fabricator()), owned while it runs.
	var/datum/fab_run/print_run

TRACKED(/obj/machinery/rnd/production, stripe_color)

CAPABILITIES(/obj/machinery/rnd/production)
	owns_one(nameof(materials), /datum/remote_materials)
	owns_one(nameof(print_sound), /datum/looping_sound/lathe_print, starts = PROC_REF(make_print_sound))
	owns_one(nameof(print_run), /datum/fab_run)
	fabricator(buildtypes = nameof(allowed_buildtypes), efficiency = nameof(efficiency_coeff), knows = PROC_REF(knows_design),
		build_time = PROC_REF(design_build_time), department = DEPARTMENT_RESEARCH, eject = TRUE, eject_power = TRUE)
	examine_line(PROC_REF(build_time_text))
	interface("Fabricator")
	extend("ui_open", needs(req_is(STAT_DISABLED, FALSE, because = MSG(rnd/disabled))))
	ui_shape(busy = bool(), materials = list_of(row()), materialChoices = list_of(row()), onHold = bool(), materialMaximum = num(), queue = list_of(row()))

/obj/machinery/rnd/production/Initialize(mapload)
	// ALLOW(decl): mapload is a constructor argument of its store: only a machine the map places links to the ore silo
	rel_set(src, nameof(materials), new /datum/remote_materials(src, mapload, mat_container_events = list((/datum/notice/matcontainer_item_consumed) = TYPE_PROC_REF(/obj/machinery/rnd/production, local_material_insert))))
	available_designs = list()
	. = ..()
	default_apply_parts()
	RefreshParts()

/obj/machinery/rnd/production/proc/make_print_sound(current)
	return new /datum/looping_sound/lathe_print(list(src), FALSE)

/obj/machinery/rnd/production/proc/build_time_text(datum/act/A)
	return span_notice("Build time at <b>[efficiency_coeff * 100]%</b>.")

// ---- the look ----

/// Its open panel and its work have their own states; a department lathe wears its stripe.
/obj/machinery/rnd/production/draw(datum/look/look)
	..()
	look.hide(LOOK_PANEL_OPEN)
	var/open = panel_open(src)
	if(open)
		look.state("[initial(icon_state)]_t")
	else if(production_animation && fabricator_printing(src))
		look.state(production_animation)
	else
		look.state(initial(icon_state))
	if(stripe_color)
		look.overlay(production_stripe(stripe_color, open))

/// A department lathe's stripe in its colour, open or shut (one shared appearance per colour and state).
/proc/production_stripe(color, open)
	var/static/list/stripes = list()
	var/key = "[color][open ? "_t" : ""]"
	var/mutable_appearance/stripe = stripes[key]
	if(!stripe)
		stripe = mutable_appearance('icons/obj/machines/research_vr.dmi', "protolathe_stripe[open ? "_t" : ""]")
		stripe.color = color
		stripes[key] = stripe
	return stripe

// ---- the techweb ----

/obj/machinery/rnd/production/connect_techweb(datum/techweb/new_techweb)
	if(stored_research)
		unobserve(stored_research, /datum/notice/techweb_add_design, src)
		unobserve(stored_research, /datum/notice/techweb_remove_design, src)
	return ..()

/obj/machinery/rnd/production/on_connected_techweb()
	. = ..()
	observe(stored_research, /datum/notice/techweb_add_design, src, then(TYPE_PROC_REF(/obj/machinery/rnd/production, on_techweb_update)))
	observe(stored_research, /datum/notice/techweb_remove_design, src, then(TYPE_PROC_REF(/obj/machinery/rnd/production, on_techweb_update)))
	update_designs()

/// Updates the list of designs this fabricator can print.
/obj/machinery/rnd/production/proc/update_designs()
	PROTECTED_PROC(TRUE)
	var/previous_design_count = available_designs.len
	available_designs.Cut()
	for(var/design_id in stored_research.researched_designs)
		var/datum/design_techweb/design = SSresearch.techweb_design_by_id(design_id)
		if(design.build_type & allowed_buildtypes)
			available_designs |= design
	var/design_delta = available_designs.len - previous_design_count
	if(design_delta > 0)
		atom_say("Received [design_delta] new design[design_delta == 1 ? "" : "s"].")
		play_sfx(src, SFX_MACHINES_TWOBEEP)
	update_static_data_for_all_viewers()

/// Designs come and go in bursts: one refresh two seconds after the first of them.
/obj/machinery/rnd/production/proc/on_techweb_update(datum/act/notice/A)
	if(!after_pending(src, "techweb_designs"))
		after(src, 2 SECONDS, PROC_REF(update_designs), key = "techweb_designs")

/// A lathe's hacked designs went (a hack pulse ran out): the window of whoever pulsed the wire shows it.
/obj/machinery/rnd/production/proc/lathe_hack_ran_out(datum/act/A)
	update_tgui_static_data(wires_last_user(src))

// ---- the fabricator's questions ----

/// It knows a researched design its department may make; a hacked design only while hacked.
/obj/machinery/rnd/production/proc/knows_design(datum/design_techweb/D)
	if(!stored_research || !LAZYACCESS(stored_research.researched_designs, D.id))
		return FALSE
	if(!isnull(allowed_department_flags) && !(D.departmental_flags & allowed_department_flags))
		return FALSE
	return hacked || !(RND_CATEGORY_HACKED in D.category)

/// One item of `D` takes this long: faster with better manipulators.
/obj/machinery/rnd/production/proc/design_build_time(datum/design_techweb/D)
	return (D.construction_time * D.lathe_time_factor * efficiency_coeff) ** 0.8

// ---- the store ----

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
/obj/machinery/rnd/production/proc/local_material_insert(datum/act/notice/N)
	var/datum/notice/matcontainer_item_consumed/event = N
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
	return 1.2 - get_part_rating(/obj/item/stock_parts/manipulator) * 0.1

// ---- the window ----

/obj/machinery/rnd/production/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/sheetmaterials),
		get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	)

/obj/machinery/rnd/production/tgui_static_data(mob/user)
	var/list/data = ..()
	var/list/designs = list()
	for(var/datum/design_techweb/design in available_designs)
		if(knows_design(design))
			designs[design.id] = fabricator_design_row(design, efficiency_coeff)
	data["designs"] = designs
	data["fabName"] = name
	var/list/material_data = materials.mat_container()?.tgui_static_data(user)
	if(material_data)
		data += material_data
	return data

/obj/machinery/rnd/production/ui_data(datum/act/eval/A)
	var/list/data = list(
		"busy" = !!fabricator_printing(src),
		// Loaded materials offered in the per-design material picker (selectable designs).
		"materialChoices" = lathe_material_choice_list(materials?.mat_container()),
		"onHold" = FALSE,
		"materialMaximum" = materials.local_size,
		"queue" = list(),
	)
	var/list/material_data = materials.mat_container()?.material_list_data(A.actor)
	if(material_data)
		data["materials"] = material_data
	return data

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
			"pressureLimit" = round(mat.pressure_limit(MATERIAL_PIPE_REFERENCE_RADIUS, MATERIAL_PIPE_REFERENCE_THICKNESS, T20C) / ONE_ATMOSPHERE, 0.1),
			"resistivity" = mat.electrical_resistivity,
			"criticalTemperature" = mat.critical_temperature,
			"criticalCurrentDensity" = mat.critical_current_density,
			"specificHeat" = mat.specific_heat,
			"phaseCapacity" = mat.phase_change_capacity,
			"phaseTemperature" = mat.phase_change_temperature,
			"dielectricStrength" = mat.dielectric_strength,
			"meltingPoint" = mat.melting_point,
		)
