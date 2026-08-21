/// Physical material-science workshop. One workpiece owns its batch from the
/// crucible charge until finished stock is struck free on the anvil.

/datum/material_batch/proc/dominant_color()
	var/datum/material/dominant
	var/dominant_amount = 0
	for(var/material_name in composition)
		if(composition[material_name] <= dominant_amount)
			continue
		dominant = get_material_by_name(material_name)
		dominant_amount = composition[material_name]
	return dominant?.icon_colour || "#8b8b8b"

/proc/material_batch_absorb_sheet(datum/material_batch/batch, obj/item/stack/material/stack)
	if(!istype(batch) || !istype(stack) || !stack.material || stack.amount < 1 || batch.amount >= MATERIAL_SCIENCE_MAX_BATCH)
		return FALSE
	stack.ensure_feedstock_lot()
	if(istype(stack.material, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = stack.material
		var/datum/material_batch/source = processed.batch_template
		for(var/component in source.composition)
			batch.add_material(component, source.composition[component] / max(source.amount, 1), null, source.purity, stack.feedstock_lot_id)
		for(var/additive in source.impurities)
			batch.impurities[additive] = (batch.impurities[additive] || 0) + source.impurities[additive] / max(source.amount, 1)
		batch.process_history += "remelted reclaimed [source.display_name()]"
	else
		batch.add_material(stack.material.name, 1, null, stack.feedstock_purity, stack.feedstock_lot_id)
		if(stack.feedstock_trace)
			batch.add_additive(stack.feedstock_trace, stack.feedstock_trace_units, 0)
	stack.use(1)
	batch.recalculate()
	return TRUE

/obj/item/reagent_containers/glass/material_crucible
	name = "refractory alloy crucible"
	desc = "A heavy open crucible. Feedstock and ordinary reagents placed inside become one persistent physical batch."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "beakerlarge"
	item_state = "beakerlarge"
	volume = 120
	amount_per_transfer_from_this = 10
	max_transfer_amount = 120
	w_class = ITEMSIZE_NORMAL
	flags = OPENCONTAINER
	resistance_flags = FIRE_PROOF | ACID_PROOF
	var/datum/material_batch/batch

/obj/item/reagent_containers/glass/material_crucible/Initialize(mapload)
	. = ..()
	batch = new
	update_icon()

/obj/item/reagent_containers/glass/material_crucible/Destroy()
	QDEL_NULL(batch)
	return ..()

/obj/item/reagent_containers/glass/material_crucible/examine(mob/user)
	. = ..()
	if(!batch?.amount)
		. += span_notice("It has no solid feedstock loaded.")
		return
	. += span_notice("It holds [round(batch.amount, 0.01)] sheets of [batch.display_name()] in the [batch.phase] phase at [round(batch.temperature)] K.")
	if(reagents.total_volume)
		. += span_notice("[round(reagents.total_volume, 0.1)] units of ordinary chemical medium surround the charge.")

/obj/item/reagent_containers/glass/material_crucible/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/stack/material))
		var/obj/item/stack/material/stack = item
		if(material_batch_absorb_sheet(batch, stack))
			user.visible_message(span_notice("[user] places a sheet into [src]."), span_notice("You add a sheet to the persistent crucible charge."))
			update_icon()
		else
			to_chat(user, span_warning("The crucible cannot accept that feedstock."))
		return
	if(istype(item, /obj/item/ore/coal))
		if(!batch?.amount)
			to_chat(user, span_warning("There is no metal charge to pack in carbon."))
			return
		batch.add_additive("carbon", 4, 0.5, MATERIAL_COST_CHEMICALS)
		batch.process_history += "packed in solid carbon"
		qdel(item)
		user.visible_message(span_notice("[user] packs coal around the charge in [src]."), span_notice("You pack the charge in carbon for diffusion during heating."))
		update_icon()
		return
	return ..()

/obj/item/reagent_containers/glass/material_crucible/update_icon()
	cut_overlays()
	name = initial(name)
	color = batch?.amount ? batch.dominant_color() : null
	if(reagents?.total_volume)
		var/mutable_appearance/filling = mutable_appearance('icons/obj/reagentfillings.dmi', "beakerlarge-40")
		filling.color = reagents.get_color()
		filling.alpha = 150
		add_overlay(filling)
	if(batch?.phase == MATERIAL_PHASE_MOLTEN)
		name = "glowing molten-alloy crucible"
		var/mutable_appearance/glow = mutable_appearance('icons/effects/effects.dmi', "shieldsparkles")
		glow.color = batch.dominant_color()
		glow.alpha = 150
		add_overlay(glow)
		set_light(2, 2, batch.dominant_color())
	else if(batch?.phase == MATERIAL_PHASE_SOLUTION)
		name = "reactive material-solution crucible"
		var/mutable_appearance/solution = mutable_appearance('icons/obj/reagentfillings.dmi', "beakerlarge-80")
		solution.color = "#79c9c2"
		solution.alpha = 190
		add_overlay(solution)
		set_light(1, 1, "#79c9c2")
	else
		set_light(0)

/obj/item/reagent_containers/glass/material_crucible/proc/release_batch()
	var/datum/material_batch/released = batch
	batch = null
	return released

/obj/item/reagent_containers/glass/material_crucible/proc/reset_batch()
	QDEL_NULL(batch)
	batch = new
	reagents.clear_reagents()
	update_icon()

/obj/item/material_workpiece
	name = "alloy workpiece"
	desc = "A persistent material workpiece. Its heat, structure, coatings, atmosphere, and field history remain physically attached to it."
	icon = 'icons/obj/mining.dmi'
	icon_state = "sheet-plastic"
	item_state = "sheet-metal"
	w_class = ITEMSIZE_NORMAL
	resistance_flags = FIRE_PROOF | ACID_PROOF
	var/datum/material_batch/batch
	var/cooling_timer

/obj/item/material_workpiece/Initialize(mapload, datum/material_batch/source_batch)
	. = ..()
	batch = source_batch || new
	update_icon()

/obj/item/material_workpiece/Destroy()
	if(cooling_timer)
		deltimer(cooling_timer)
		cooling_timer = null
	QDEL_NULL(batch)
	return ..()

/obj/item/material_workpiece/proc/release_batch()
	var/datum/material_batch/released = batch
	batch = null
	return released

/obj/item/material_workpiece/proc/material_is_hot()
	return batch?.temperature >= max(T0C + 180, batch.melting_temperature() * 0.35)

/obj/item/material_workpiece/proc/coating_color()
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_BLUESPACE]) return "#735cff"
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_CONDUCTIVE]) return "#ffe75c"
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_CRYO]) return "#63b8ff"
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_THERMAL]) return "#ff7b32"
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_CORROSION]) return "#72268f"
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_CATALYTIC]) return "#e0bd45"
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_METAL]) return "#a7abb4"
	if(batch.impurities["silver plating"]) return "#d9e3e8"
	if(batch.impurities["gold plating"]) return "#e6b93f"
	if(batch.impurities["platinum plating"]) return "#b9d7dc"
	if(batch.surface_layers[MATERIAL_SURFACE_CARBON]) return "#242424"
	if(batch.surface_layers[MATERIAL_SURFACE_OXIDE]) return "#8b4b2c"
	return null

/obj/item/material_workpiece/update_icon()
	cut_overlays()
	if(!batch)
		return
	icon_state = batch.phase == MATERIAL_PHASE_POWDER ? "ore2" : "sheet-plastic"
	var/base_color = batch.dominant_color()
	var/heat_ratio = batch.temperature / max(batch.melting_temperature(), 1)
	if(heat_ratio >= 0.9)
		color = "#fff2bd"
	else if(heat_ratio >= 0.72)
		color = "#ffb12b"
	else if(heat_ratio >= 0.5)
		color = "#e74820"
	else
		color = coating_color() || base_color
	if(material_is_hot())
		var/mutable_appearance/heat = mutable_appearance('icons/effects/effects.dmi', "shieldsparkles")
		heat.color = color
		heat.alpha = 120
		add_overlay(heat)
		set_light(clamp(round(heat_ratio * 3), 1, 3), 2, color)
	else
		set_light(0)
	if(length(batch.field_treatments))
		var/mutable_appearance/field = mutable_appearance('icons/effects/effects.dmi', "lightning")
		field.color = "#8fbaff"
		field.alpha = 90
		add_overlay(field)
	if(batch.phase == MATERIAL_PHASE_POWDER)
		name = "granular material charge"
	else
		name = material_is_hot() ? "glowing alloy workpiece" : "alloy workpiece"
	schedule_natural_cooling()

/obj/item/material_workpiece/proc/schedule_natural_cooling()
	if(cooling_timer || !batch || batch.temperature <= T20C + 3)
		return
	cooling_timer = addtimer(CALLBACK(src, PROC_REF(natural_cooling_tick)), 2 SECONDS, TIMER_STOPPABLE)

/obj/item/material_workpiece/proc/natural_cooling_tick()
	cooling_timer = null
	if(!batch)
		return
	if(istype(loc, /obj/machinery/material_furnace))
		var/obj/machinery/material_furnace/furnace = loc
		if(furnace.firing)
			schedule_natural_cooling()
			return
	var/turf/work_turf = get_turf(src)
	var/datum/gas_mixture/air = work_turf?.return_air()
	var/ambient_temperature = air?.return_temperature() || TCMB
	var/temperature_difference = batch.temperature - ambient_temperature
	if(temperature_difference <= 3)
		return
	var/workpiece_capacity = max(batch.amount * 1000, 1000)
	var/air_capacity = air?.heat_capacity() || 0
	if(air_capacity > 0)
		var/transfer = temperature_difference * ((workpiece_capacity * air_capacity) / (workpiece_capacity + air_capacity)) * 0.15
		batch.temperature -= transfer / workpiece_capacity
		air.set_temperature((air.thermal_energy() + transfer) / air_capacity)
	else
		batch.temperature = max(ambient_temperature, batch.temperature - 20)
	batch.temperature = max(ambient_temperature, batch.temperature)
	update_icon()

/obj/item/material_workpiece/examine(mob/user)
	. = ..()
	if(!batch)
		return
	. += span_notice("[batch.display_name()], [batch.phase], [round(batch.temperature)] K; [round(batch.yield_fraction * 100)]% retained yield.")
	if(length(batch.surface_layers))
		. += span_notice("Visible surface layers: [jointext(batch.surface_layers, ", ")].")
	if(length(batch.dissolved_gases))
		. += span_notice("Entrained gas signatures: [jointext(batch.dissolved_gases, ", ")].")
	if(length(batch.field_treatments))
		. += span_notice("The lattice carries [jointext(batch.field_treatments, ", ")].")
	if(length(batch.test_results))
		var/list/observations = list()
		for(var/observation in batch.test_results)
			observations += "[observation]: [batch.test_results[observation]]"
		. += span_notice("Physical observations: [jointext(observations, "; ")].")
	. += span_notice("Batch fingerprint [copytext(batch.fingerprint(), 1, 9)].")

/obj/item/material_workpiece/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/slime_extract))
		return apply_slime_skin(item, user)
	if(istype(item, /obj/item/ore/coal))
		if(!material_is_hot())
			to_chat(user, span_warning("The workpiece must be glowing before carbon will diffuse into its surface."))
			return
		batch.add_surface_layer(MATERIAL_SURFACE_CARBON, 35, "carbon", 3)
		qdel(item)
		visible_message(span_notice("Carbon blackens, then visibly diffuses into [src]'s glowing surface."))
		update_icon()
		return
	if(item.type == /obj/item/analyzer)
		batch.test_results[MATERIAL_TEST_SPECTROMETRY] = batch.purity
		batch.test_results[MATERIAL_TEST_MICROSCOPY] = 100 - batch.structure[MATERIAL_STRUCTURE_DEFECT]
		to_chat(user, span_notice("The analyzer resolves [json_encode(batch.composition)] at [batch.purity]% purity and [batch.temperature] K. Surface and lattice discontinuities are recorded on the workpiece."))
		return
	if(istype(item, /obj/item/multitool))
		batch.test_results[MATERIAL_TEST_CONDUCTIVITY] = batch.conductivity
		to_chat(user, span_notice("The probes report [batch.conductivity]% relative conductivity. The observation is written into the workpiece's field notes."))
		if(material_is_hot() && (batch.composition[MAT_IRON] || batch.composition[MAT_STEEL]))
			batch.add_field_treatment(MATERIAL_FIELD_MAGNETIC, 15)
			visible_message(span_notice("Fine ferrous lines visibly align across [src] under the multitool's field."))
			update_icon()
		return
	return ..()

/obj/item/material_workpiece/proc/apply_slime_skin(obj/item/slime_extract/extract, mob/user)
	if(!batch || !extract.uses)
		to_chat(user, span_warning("The extract is inert."))
		return TRUE
	if(!material_is_hot())
		to_chat(user, span_warning("The workpiece must be glowing for the slime matrix to bond."))
		return TRUE
	var/layer_name
	var/additive_name
	if(istype(extract, /obj/item/slime_extract/metal))
		layer_name = MATERIAL_SURFACE_SLIME_METAL
		additive_name = "metallic grain refiner"
		batch.structure[MATERIAL_STRUCTURE_REINFORCEMENT] += 14
	else if(istype(extract, /obj/item/slime_extract/blue))
		layer_name = MATERIAL_SURFACE_SLIME_CRYO
		additive_name = "cryogenic stabilizer"
		batch.internal_stress = clamp(batch.internal_stress - 18, 0, 100)
	else if(istype(extract, /obj/item/slime_extract/orange))
		layer_name = MATERIAL_SURFACE_SLIME_THERMAL
		additive_name = "thermal phase catalyst"
	else if(istype(extract, /obj/item/slime_extract/yellow))
		layer_name = MATERIAL_SURFACE_SLIME_CONDUCTIVE
		additive_name = "conductive dopant"
	else if(istype(extract, /obj/item/slime_extract/dark_purple))
		layer_name = MATERIAL_SURFACE_SLIME_CORROSION
		additive_name = "corrosion inhibitor"
	else if(istype(extract, /obj/item/slime_extract/gold))
		layer_name = MATERIAL_SURFACE_SLIME_CATALYTIC
		additive_name = "precipitation catalyst"
		batch.structure[MATERIAL_STRUCTURE_PRECIPITATE] += 16
	else if(istype(extract, /obj/item/slime_extract/bluespace))
		layer_name = MATERIAL_SURFACE_SLIME_BLUESPACE
		additive_name = "bluespace homogenizer"
		batch.homogeneity = clamp(batch.homogeneity + 24, 0, 100)
	else
		layer_name = "[extract.name] organic skin"
		additive_name = "[extract.name] organic matrix"
		batch.structure[MATERIAL_STRUCTURE_AMORPHOUS] += 12
	batch.add_surface_layer(layer_name, 35, additive_name, 4)
	batch.normalize_structure()
	batch.purity = clamp(batch.purity + 2, 0, 100)
	batch.recalculate()
	extract.uses--
	if(extract.uses <= 0)
		extract.name = "inert [initial(extract.name)]"
	visible_message(span_notice("[extract] liquefies over [src], leaving a moving [layer_name] bonded to the surface."))
	update_icon()
	return TRUE

/obj/machinery/material_furnace
	name = "controlled-atmosphere alloy hearth"
	desc = "A physical alloy hearth. Its open chamber uses the room's real pressure and gas mixture during every firing."
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "nt_cruciforge"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 5000
	circuit = /obj/item/circuitboard/machine/material_furnace
	var/obj/item/reagent_containers/glass/material_crucible/crucible
	var/obj/item/material_workpiece/workpiece
	var/firing
	var/firing_timer

/obj/machinery/material_furnace/Destroy()
	if(firing_timer)
		deltimer(firing_timer)
		firing_timer = null
	crucible = null
	workpiece = null
	return ..()

/obj/machinery/material_furnace/examine(mob/user)
	. = ..()
	if(crucible)
		. += span_notice("A [crucible] is seated in the chamber.")
	else if(workpiece)
		. += span_notice("A [workpiece] is seated in the chamber.")
	else
		. += span_notice("The chamber is empty. Insert a crucible or solid workpiece.")
	var/turf/furnace_turf = get_turf(src)
	var/datum/gas_mixture/air = furnace_turf?.return_air()
	if(air)
		. += span_notice("The open chamber reads [round(air.return_pressure(), 0.1)] kPa at [round(air.return_temperature(), 0.1)] K.")

/obj/machinery/material_furnace/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/reagent_containers/glass/material_crucible))
		if(crucible || workpiece || firing)
			to_chat(user, span_warning("The hearth is already occupied."))
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		crucible = item
		to_chat(user, span_notice("You seat [item] in the exposed chamber."))
		return
	if(istype(item, /obj/item/material_workpiece))
		if(crucible || workpiece || firing)
			to_chat(user, span_warning("The hearth is already occupied."))
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		workpiece = item
		to_chat(user, span_notice("You seat [item] in the hearth for structural heat treatment."))
		return
	if(item.has_tool_quality(TOOL_CROWBAR) && !firing)
		eject_contents(user)
		return
	return ..()

/obj/machinery/material_furnace/attack_hand(mob/user)
	if(..())
		return TRUE
	if(firing || (!crucible && !workpiece) || (stat & (BROKEN | NOPOWER)))
		to_chat(user, span_warning(firing ? "The hearth is already roaring." : "The hearth cannot begin a firing."))
		return TRUE
	firing = TRUE
	icon_state = "nt_cruciforge_work"
	use_power(active_power_usage * 6)
	visible_message(span_notice("[src]'s exposed chamber closes around the charge and blooms with visible heat."))
	set_light(3, 3, "#ff7b22")
	firing_timer = addtimer(CALLBACK(src, PROC_REF(finish_firing)), 6 SECONDS, TIMER_STOPPABLE)
	return TRUE

/obj/machinery/material_furnace/proc/finish_firing()
	firing_timer = null
	firing = FALSE
	icon_state = "nt_cruciforge"
	set_light(0)
	var/datum/material_batch/batch = crucible?.batch || workpiece?.batch
	if(!batch?.amount)
		visible_message(span_warning("[src] opens on an empty charge."))
		return
	if(crucible)
		var/entered_solution = process_crucible_chemistry(batch)
		if(batch.phase == MATERIAL_PHASE_SOLUTION && !entered_solution)
			batch.temperature = max(batch.temperature, T20C + 100)
			batch.apply_process(MATERIAL_PROCESS_CRYSTALLIZE)
		else if(batch.phase == MATERIAL_PHASE_POWDER)
			batch.apply_process(MATERIAL_PROCESS_SINTER)
		else if(batch.phase == MATERIAL_PHASE_SOLID)
			batch.temperature = batch.melting_temperature() + 50
			batch.apply_process(MATERIAL_PROCESS_MELT)
		else if(batch.phase == MATERIAL_PHASE_MOLTEN)
			batch.apply_process(MATERIAL_PROCESS_HOMOGENIZE)
		crucible.update_icon()
	else
		if(batch.phase == MATERIAL_PHASE_POWDER)
			batch.temperature = round(batch.melting_temperature() * 0.6)
			batch.apply_process(MATERIAL_PROCESS_SINTER)
		else if(batch.structure[MATERIAL_STRUCTURE_HARDENED] >= 15)
			batch.temperature = round(batch.melting_temperature() * 0.32)
			batch.apply_process(MATERIAL_PROCESS_TEMPER)
		else
			batch.temperature = round(batch.melting_temperature() * 0.72)
			batch.apply_process(MATERIAL_PROCESS_SOLUTION_TREAT)
		workpiece.update_icon()
	apply_real_atmosphere(batch)
	visible_message(span_notice("[src] opens, revealing the visibly transformed [crucible || workpiece]."))

/obj/machinery/material_furnace/proc/process_crucible_chemistry(datum/material_batch/batch)
	if(!crucible?.reagents?.total_volume)
		return FALSE
	var/entered_solution = FALSE
	var/acid = crucible.reagents.get_reagent_amount(REAGENT_ID_SACID) + crucible.reagents.get_reagent_amount(REAGENT_ID_PACID)
	var/carbon = crucible.reagents.get_reagent_amount(REAGENT_ID_CARBON)
	var/silicon = crucible.reagents.get_reagent_amount(REAGENT_ID_SILICON)
	if(carbon) batch.add_additive("carbon", min(carbon, 8), 1, MATERIAL_COST_CHEMICALS)
	if(silicon) batch.add_additive("silicon", min(silicon, 6), 1, MATERIAL_COST_CHEMICALS)
	if(acid >= 5 && batch.phase == MATERIAL_PHASE_SOLID)
		batch.apply_process(MATERIAL_PROCESS_DISSOLVE)
		batch.purity = clamp(batch.purity + min(round(acid / 2), 12), 0, 100)
		entered_solution = TRUE
	for(var/datum/reagent/reagent in crucible.reagents.reagent_list)
		if(reagent.id in list(REAGENT_ID_CARBON, REAGENT_ID_SILICON, REAGENT_ID_SACID, REAGENT_ID_PACID))
			continue
		batch.add_additive(reagent.name, min(reagent.volume, 6), max(reagent.supply_conversion_value, 0.05), MATERIAL_COST_CHEMICALS)
	batch.process_history += "chemically treated in [round(crucible.reagents.total_volume, 0.1)]u ordinary reagent medium"
	crucible.reagents.clear_reagents()
	return entered_solution

/obj/machinery/material_furnace/proc/apply_real_atmosphere(datum/material_batch/batch)
	var/turf/furnace_turf = get_turf(src)
	var/datum/gas_mixture/air = furnace_turf?.return_air()
	if(!air)
		return
	var/pressure = air.return_pressure()
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/nitrogen = air.get_moles(/datum/gas/nitrogen)
	var/hydrogen = air.get_moles(/datum/gas/hydrogen)
	var/phoron = air.get_moles(/datum/gas/plasma)
	var/uptake_scale = clamp(pressure / ONE_ATMOSPHERE, 0, 5)
	if(pressure < 20)
		batch.atmosphere = MATERIAL_ATMOSPHERE_VACUUM
		batch.purity = clamp(batch.purity + 3, 0, 100)
		batch.porosity = clamp(batch.porosity - 4, 0, 100)
		batch.process_history += "vacuum degassed"
	else if(hydrogen > oxygen * 0.25)
		var/hydrogen_used = min(hydrogen, 0.08 * uptake_scale)
		batch.atmosphere = MATERIAL_ATMOSPHERE_REDUCING
		batch.add_dissolved_gas("hydrogen", hydrogen_used * 25)
		batch.oxidation = clamp(batch.oxidation - 8, 0, 100)
		air.adjust_moles(/datum/gas/hydrogen, -hydrogen_used)
	else
		batch.atmosphere = MATERIAL_ATMOSPHERE_AIR
	if(nitrogen > 0.1 && pressure >= 40)
		var/nitrogen_used = min(nitrogen, 0.04 * uptake_scale)
		batch.add_dissolved_gas("nitrogen", nitrogen_used * 25)
		air.adjust_moles(/datum/gas/nitrogen, -nitrogen_used)
	if(oxygen > 0.1 && batch.temperature >= batch.melting_temperature() * 0.5)
		var/oxygen_used = min(oxygen, 0.03 * uptake_scale)
		batch.add_dissolved_gas("oxygen", oxygen_used * 20)
		batch.oxidation = clamp(batch.oxidation + round(oxygen_used * 80), 0, 100)
		batch.add_surface_layer(MATERIAL_SURFACE_OXIDE, max(1, round(oxygen_used * 100)))
		air.adjust_moles(/datum/gas/oxygen, -oxygen_used)
		air.adjust_moles(/datum/gas/carbon_dioxide, oxygen_used)
	if(phoron > 0.05)
		var/phoron_used = min(phoron, 0.025 * uptake_scale)
		batch.add_dissolved_gas("phoron", phoron_used * 40)
		batch.add_additive("phoron interstitial", phoron_used * 20, 3, MATERIAL_COST_CHEMICALS)
		air.adjust_moles(/datum/gas/plasma, -phoron_used)
	batch.recalculate()

/obj/machinery/material_furnace/proc/eject_contents(mob/user)
	var/turf/furnace_turf = get_turf(src)
	if(crucible)
		crucible.forceMove(furnace_turf)
		crucible = null
	else if(workpiece)
		workpiece.forceMove(furnace_turf)
		workpiece = null
	else
		return
	to_chat(user, span_notice("You lever the physical charge out of [src]."))

/obj/structure/material_anvil
	name = "materials anvil"
	desc = "A massive anvil for pouring, forging, and finally striking processed stock free."
	icon = 'icons/obj/props/fantasy.dmi'
	icon_state = "anvil"
	anchored = TRUE
	density = TRUE
	var/obj/item/material_workpiece/workpiece

/obj/structure/material_anvil/Destroy()
	workpiece = null
	return ..()

/obj/structure/material_anvil/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/reagent_containers/glass/material_crucible))
		var/obj/item/reagent_containers/glass/material_crucible/crucible = item
		if(workpiece || crucible.batch?.phase != MATERIAL_PHASE_MOLTEN)
			to_chat(user, span_warning(workpiece ? "The anvil already holds a workpiece." : "Only a molten charge can be poured into a workpiece."))
			return
		var/datum/material_batch/poured_batch = crucible.release_batch()
		poured_batch.apply_process(MATERIAL_PROCESS_CAST, "workpiece")
		workpiece = new /obj/item/material_workpiece(src, poured_batch)
		crucible.reset_batch()
		visible_message(span_notice("[user] pours a glowing charge from [crucible] across [src], forming one persistent workpiece."))
		playsound(src, 'sound/effects/clang.ogg', 50, TRUE)
		return
	if(istype(item, /obj/item/material_workpiece))
		if(workpiece)
			to_chat(user, span_warning("The anvil already holds a workpiece."))
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		workpiece = item
		return
	if(istype(item, /obj/item/melee/hammer))
		if(!workpiece?.batch)
			to_chat(user, span_warning("There is no workpiece to strike."))
			return
		if(workpiece.material_is_hot() && workpiece.batch.can_process(MATERIAL_PROCESS_FORGE))
			workpiece.batch.apply_process(MATERIAL_PROCESS_FORGE)
			workpiece.batch.test_results[MATERIAL_TEST_HARDNESS] = workpiece.batch.hardness
			workpiece.batch.test_results[MATERIAL_TEST_TENSILE] = workpiece.batch.toughness
			workpiece.batch.temperature = max(T20C, workpiece.batch.temperature - 80)
			workpiece.update_icon()
			visible_message(span_notice("[user] drives a deliberate blow through [workpiece]; sparks trace the grain as voids close."))
			playsound(src, 'sound/effects/clang2.ogg', 70, TRUE)
			return
		if(workpiece.batch.temperature > T0C + 120)
			to_chat(user, span_warning("The workpiece is outside its forging window. Let it cool or heat-treat it correctly."))
			return
		var/datum/material_batch/finished_batch = workpiece.release_batch()
		processed_spawn_stack(get_turf(src), finished_batch, max(1, round(finished_batch.amount * finished_batch.yield_fraction)))
		emit_contract_event(CONTRACT_EVENT_MATERIAL_PROCESSED, finished_batch.evidence_context("physical workshop finish"))
		emit_contract_event(CONTRACT_EVENT_MATERIAL_CERTIFIED, finished_batch.evidence_context("finished physical stock"), finished_batch.fingerprint(), src, user)
		qdel(finished_batch)
		qdel(workpiece)
		workpiece = null
		visible_message(span_notice("[user] strikes away the final scale; finished material stock separates from [src]."))
		playsound(src, 'sound/effects/clang.ogg', 60, TRUE)
		return
	return ..()

/obj/structure/material_anvil/attack_hand(mob/user)
	if(!workpiece)
		return ..()
	workpiece.forceMove(get_turf(src))
	workpiece = null
	to_chat(user, span_notice("You lift the workpiece from [src]."))
	return TRUE

/obj/structure/material_grindstone
	name = "materials grindstone"
	desc = "A physical grinding wheel for reducing a cool workpiece to particulate feedstock. Powder can be sintered into porous structures in the hearth."
	icon = 'icons/obj/props/fantasy.dmi'
	icon_state = "grindstone"
	anchored = TRUE
	density = TRUE
	var/obj/item/material_workpiece/workpiece

/obj/structure/material_grindstone/Destroy()
	workpiece = null
	return ..()

/obj/structure/material_grindstone/attackby(obj/item/item, mob/user)
	if(!istype(item, /obj/item/material_workpiece))
		return ..()
	if(workpiece)
		to_chat(user, span_warning("The grindstone already holds a workpiece."))
		return
	var/obj/item/material_workpiece/new_workpiece = item
	if(new_workpiece.material_is_hot() || new_workpiece.batch.phase != MATERIAL_PHASE_SOLID)
		to_chat(user, span_warning("Only a cool solid workpiece can be ground."))
		return
	user.drop_from_inventory(new_workpiece)
	new_workpiece.forceMove(src)
	workpiece = new_workpiece
	to_chat(user, span_notice("You brace [workpiece] against [src]. Turn the wheel to grind it."))

/obj/structure/material_grindstone/attack_hand(mob/user)
	if(!workpiece)
		return ..()
	if(!do_after(user, 4 SECONDS, target = src) || !workpiece)
		return TRUE
	if(!workpiece.batch.apply_process(MATERIAL_PROCESS_PULVERIZE))
		to_chat(user, span_warning("The workpiece cannot be reduced in its present state."))
		return TRUE
	workpiece.update_icon()
	visible_message(span_notice("[user] works [src]; the workpiece becomes a visibly granular particulate charge."))
	playsound(src, 'sound/effects/clang.ogg', 30, TRUE)
	return TRUE

/obj/structure/material_grindstone/click_alt(mob/user)
	if(!workpiece)
		return CLICK_ACTION_BLOCKING
	workpiece.forceMove(get_turf(src))
	workpiece = null
	return CLICK_ACTION_SUCCESS

/obj/structure/bed/bath/material_treatment
	name = "open material-treatment trough"
	desc = "An open bath using ordinary reagents for quenching, etching, and electroplating. Its contents, not a menu, determine the treatment."
	can_buckle = FALSE
	buckle_lying = FALSE
	flippable = FALSE
	amount_per_transfer_from_this = 10
	var/obj/item/cell/electrode_cell

/obj/structure/bed/bath/material_treatment/Destroy()
	electrode_cell = null
	return ..()

/obj/structure/bed/bath/material_treatment/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/cell))
		if(electrode_cell)
			to_chat(user, span_warning("The trough already has an electrode cell clipped in."))
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		electrode_cell = item
		to_chat(user, span_notice("You clip [item] across the trough's exposed electrodes."))
		return
	if(!istype(item, /obj/item/material_workpiece))
		return ..()
	var/obj/item/material_workpiece/workpiece = item
	if(!reagents?.total_volume)
		to_chat(user, span_warning("The treatment trough is empty."))
		return
	if(workpiece.material_is_hot())
		return quench_workpiece(workpiece, user)
	return chemically_treat_workpiece(workpiece, user)

/obj/structure/bed/bath/material_treatment/proc/quench_workpiece(obj/item/material_workpiece/workpiece, mob/user)
	var/medium
	var/reagent_id
	if(reagents.has_reagent(REAGENT_ID_FROSTOIL, 5))
		medium = "cryo"; reagent_id = REAGENT_ID_FROSTOIL
	else if(reagents.has_reagent(REAGENT_ID_COOKINGOIL, 5))
		medium = "oil"; reagent_id = REAGENT_ID_COOKINGOIL
	else if(reagents.has_reagent(REAGENT_ID_WATER, 5))
		medium = "water"; reagent_id = REAGENT_ID_WATER
	else
		to_chat(user, span_warning("The bath has no usable water, cooking oil, or frostoil quench medium."))
		return TRUE
	if(!workpiece.batch.solution_treated)
		to_chat(user, span_warning("The lattice was not brought through a solution-treatment heat; immersion only cools it."))
		workpiece.batch.temperature = T20C
		workpiece.update_icon()
		return TRUE
	reagents.remove_reagent(reagent_id, 5)
	workpiece.batch.apply_process(MATERIAL_PROCESS_QUENCH, medium)
	workpiece.batch.test_results[MATERIAL_TEST_HARDNESS] = workpiece.batch.hardness
	workpiece.update_icon()
	playsound(src, 'sound/effects/slosh.ogg', 40, TRUE)
	visible_message(span_notice(medium == "cryo" ? "Frost races over [workpiece] in a blue-white flash." : (medium == "oil" ? "A brief sheet of flame rolls across [workpiece]." : "A dense cloud of steam erupts around [workpiece].")))
	update_icon()
	return TRUE

/obj/structure/bed/bath/material_treatment/proc/chemically_treat_workpiece(obj/item/material_workpiece/workpiece, mob/user)
	var/datum/material_batch/batch = workpiece.batch
	var/plating_id
	var/plating_name
	if(reagents.has_reagent(REAGENT_ID_SILVER, 5))
		plating_id = REAGENT_ID_SILVER; plating_name = "silver plating"
	else if(reagents.has_reagent(REAGENT_ID_PLATINUM, 5))
		plating_id = REAGENT_ID_PLATINUM; plating_name = "platinum plating"
	else if(reagents.has_reagent(REAGENT_ID_GOLD, 5))
		plating_id = REAGENT_ID_GOLD; plating_name = "gold plating"
	if(plating_id)
		if(!electrode_cell || electrode_cell.use(100) < 100)
			to_chat(user, span_warning("Electroplating requires a charged power cell clipped across the trough's exposed electrodes."))
			return TRUE
		reagents.remove_reagent(plating_id, 5)
		batch.add_surface_layer(MATERIAL_SURFACE_PLATING, 25, plating_name, 5)
		batch.surface_protection = clamp(batch.surface_protection + 12, 0, 30)
		batch.test_results[MATERIAL_TEST_CORROSION] = batch.corrosion_resistance
		visible_message(span_notice("Current crawls through the open bath as a visible [plating_name] grows across [workpiece]."))
		workpiece.update_icon(); update_icon()
		return TRUE
	var/acid = reagents.get_reagent_amount(REAGENT_ID_SACID) + reagents.get_reagent_amount(REAGENT_ID_PACID)
	if(acid >= 5)
		var/used_sacid = min(5, reagents.get_reagent_amount(REAGENT_ID_SACID))
		if(used_sacid) reagents.remove_reagent(REAGENT_ID_SACID, used_sacid)
		if(used_sacid < 5) reagents.remove_reagent(REAGENT_ID_PACID, 5 - used_sacid)
		batch.porosity = clamp(batch.porosity + 8, 0, 100)
		batch.surface_layers -= MATERIAL_SURFACE_OXIDE
		batch.process_history += "acid etched in an open chemical bath"
		batch.test_results[MATERIAL_TEST_CORROSION] = batch.corrosion_resistance
		batch.recalculate()
		visible_message(span_notice("Acid fizzes across [workpiece], stripping scale and opening a visibly porous surface."))
		workpiece.update_icon(); update_icon()
		return TRUE
	to_chat(user, span_warning("Those ordinary reagents do not produce a stable treatment on this cool workpiece."))
	return TRUE

/obj/structure/bed/bath/material_treatment/click_alt(mob/user)
	if(!electrode_cell)
		return CLICK_ACTION_BLOCKING
	electrode_cell.forceMove(get_turf(src))
	electrode_cell = null
	to_chat(user, span_notice("You unclip the trough's electrode cell."))
	return CLICK_ACTION_SUCCESS

/obj/machinery/particle_smasher/proc/try_material_workpiece_conditioning()
	if(energy < 350 || !istype(target, /obj/item/material_workpiece))
		return FALSE
	var/obj/item/material_workpiece/workpiece = target
	if(!workpiece.batch || workpiece.batch.field_treatments[MATERIAL_FIELD_PARTICLE] >= 100)
		return FALSE
	var/strength = clamp(round(energy / 6), 20, 100)
	workpiece.batch.add_field_treatment(MATERIAL_FIELD_PARTICLE, strength)
	if(workpiece.batch.composition[MAT_IRON] || workpiece.batch.composition[MAT_STEEL])
		workpiece.batch.add_field_treatment(MATERIAL_FIELD_MAGNETIC, round(strength / 2))
	workpiece.batch.homogeneity = clamp(workpiece.batch.homogeneity + round(strength / 8), 0, 100)
	workpiece.batch.test_results[MATERIAL_TEST_FIELD] = strength
	workpiece.batch.recalculate()
	workpiece.update_icon()
	energy = max(0, energy - 300)
	visible_message(span_notice("Particle arcs lock into [workpiece]; luminous lines remain suspended through its conditioned lattice."))
	update_icon()
	return TRUE

/obj/item/circuitboard/machine/material_furnace
	name = T_BOARD("controlled-atmosphere alloy hearth")
	build_path = /obj/machinery/material_furnace
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stock_parts/matter_bin = 2,
		/obj/item/stock_parts/manipulator = 1,
		/obj/item/stock_parts/micro_laser = 2,
	)

/datum/design_techweb/board/material_furnace
	SET_CIRCUIT_DESIGN_NAMEDESC("controlled-atmosphere alloy hearth")
	id = "board_material_furnace"
	build_path = /obj/item/circuitboard/machine/material_furnace
	category = list(RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_MACHINE_RESEARCH)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_ENGINEERING

/datum/design_techweb/material_crucible
	name = "Refractory Alloy Crucible"
	desc = "A reusable open crucible for physically carrying persistent material charges and ordinary chemical media."
	id = "material_crucible"
	build_type = AUTOLATHE | PROTOLATHE
	materials = list(MAT_STEEL = 1000, MAT_GLASS = 500)
	category = list(RND_CATEGORY_INITIAL, RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_EQUIPMENT_CHEMISTRY)
	build_path = /obj/item/reagent_containers/glass/material_crucible
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_ENGINEERING
