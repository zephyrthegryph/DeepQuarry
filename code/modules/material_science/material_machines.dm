/// Physical material workshop. Inputs and outputs are always ordinary material
/// stacks; machines never expose a bespoke batch carrier or workpiece item.

/datum/material_batch/proc/dominant_color()
	var/datum/material/dominant
	var/dominant_amount = 0
	for(var/material_name in composition)
		if(LAZYACCESS(composition, material_name) > dominant_amount)
			dominant = get_material_by_name(material_name)
			dominant_amount = LAZYACCESS(composition, material_name)
	return dominant?.icon_colour || "#8b8b8b"

/proc/material_batch_absorb_sheet(datum/material_batch/batch, obj/item/stack/material/stack)
	if(!istype(batch) || !istype(stack) || !stack.material || stack.amount < 1 || batch.amount >= MATERIAL_SCIENCE_MAX_BATCH)
		return FALSE
	stack.ensure_feedstock_lot()
	if(istype(stack.material, /datum/material/processed_alloy))
		var/obj/item/stack/material/processed_alloy/processed_stack = stack
		var/datum/material_batch/source = processed_stack.physical_batch()
		for(var/component in source.composition)
			batch.add_material(component, LAZYACCESS(source.composition, component) / max(source.amount, 1), null, source.purity, stack.feedstock_lot_id)
		for(var/additive in source.impurities)
			LAZYSET(batch.impurities, additive, (LAZYACCESS(batch.impurities, additive) || 0) + LAZYACCESS(source.impurities, additive) / max(source.amount, 1))
		// Reclaimed stock offsets part of its fresh-feedstock cost. Coatings and
		// field treatments are deliberately destroyed by remelting, but the
		// recovered metal is now economically and contractually traceable.
		batch.record_recovery(max(0.1, source.unit_production_cost() * 0.5))
		LAZYADD(batch.process_history, "remelted reclaimed [source.display_name()]")
	else
		batch.add_material(stack.material.name, 1, null, stack.feedstock_purity, stack.feedstock_lot_id)
		if(stack.feedstock_trace)
			batch.add_additive(stack.feedstock_trace, stack.feedstock_trace_units, 0)
	stack.use(1)
	batch.recalculate()
	return TRUE

/proc/replace_processed_stack(obj/item/stack/material/old_stock, datum/material_batch/new_batch, atom/location)
	if(!istype(old_stock) || !istype(new_batch))
		return null
	var/amount = old_stock.get_amount()
	var/obj/item/stack/material/processed_alloy/replacement = processed_spawn_stack(get_turf(location || old_stock), new_batch, amount)
	qdel(old_stock)
	return replacement

/obj/machinery/material_furnace
	name = "controlled-atmosphere alloy furnace"
	desc = "A sealed furnace for melting, alloying, and heat-treating material sheets. Click it to fire a loaded charge or collect its finished alloy."
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "nt_cruciforge"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 5000
	circuit = /obj/item/circuitboard/machine/material_furnace
	var/list/feedstock
	var/list/carbon_feed
	var/obj/item/stack/material/processed_alloy/output_stock
	var/firing = FALSE
	var/firing_timer
	var/datum/gas_mixture/chamber_air

/obj/machinery/material_furnace/Initialize(mapload)
	. = ..()
	chamber_air = new(500)
	var/turf/furnace_turf = get_turf(src)
	var/datum/gas_mixture/environment = furnace_turf?.return_air()
	if(environment)
		chamber_air.copy_from(environment)
	create_reagents(120)

/obj/machinery/material_furnace/Destroy()
	if(firing_timer)
		deltimer(firing_timer)
		firing_timer = null
	feedstock = null
	carbon_feed = null
	output_stock = null
	QDEL_NULL(chamber_air)
	return ..()

/obj/machinery/material_furnace/examine(mob/user)
	. = ..()
	. += span_notice("Loaded stock: [LAZYLEN(feedstock)] stack(s); chemical medium: [round(reagents?.total_volume || 0, 0.1)]u.")
	if(output_stock)
		. += span_notice("Finished alloy is ready. Click the furnace to collect it.")
	else if(LAZYLEN(feedstock))
		. += span_notice("The charge is ready. Click to fire it, or use Eject contents to unload it.")
	if(chamber_air)
		. += span_notice("Chamber: [round(chamber_air.return_pressure(), 0.1)] kPa at [round(chamber_air.return_temperature(), 0.1)] K.")

/obj/machinery/material_furnace/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/stack/material))
		if(firing || output_stock)
			to_chat(user, span_warning("The furnace must be idle and its output removed first."))
			return
		var/obj/item/stack/material/stock = item
		user.drop_from_inventory(stock)
		stock.forceMove(src)
		LAZYADD(feedstock, stock)
		visible_message(span_notice("[user] loads [stock] into [src]."))
		return
	if(istype(item, /obj/item/ore/coal))
		if(firing || output_stock)
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		LAZYADD(carbon_feed, item)
		visible_message(span_notice("[user] adds carbon to [src]'s charge."))
		return
	if(istype(item, /obj/item/tank))
		if(firing)
			return
		var/obj/item/tank/tank = item
		var/from_tank = tank.air_contents?.return_pressure() > chamber_air.return_pressure()
		var/datum/gas_mixture/charge = from_tank ? tank.air_contents?.remove(5) : chamber_air.remove(5)
		if(charge)
			if(from_tank)
				chamber_air.merge(charge)
			else
				tank.air_contents.merge(charge)
			qdel(charge)
			visible_message(span_notice("[user] transfers gas [from_tank ? "from [tank] into" : "from [src] into"] the furnace chamber."))
		return
	if(istype(item, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/container = item
		if(container.reagents?.total_volume)
			var/transferred = container.reagents.trans_to(src, min(10, container.reagents.total_volume))
			if(transferred)
				to_chat(user, span_notice("You pour [round(transferred, 0.1)] units from [container] into the furnace chamber."))
				return
	return ..()

/obj/machinery/material_furnace/attack_hand(mob/user)
	if(..())
		return TRUE
	if(output_stock && !firing)
		var/obj/item/stack/material/processed_alloy/finished = output_stock
		output_stock = null
		finished.forceMove(user.drop_location())
		user.put_in_hands(finished)
		visible_message(span_notice("[user] removes [finished] from [src]'s output tray."))
		return TRUE
	if(firing)
		to_chat(user, span_warning("The furnace is still firing."))
		return TRUE
	if(!LAZYLEN(feedstock))
		to_chat(user, span_notice("The furnace is empty. Load material sheets before firing it."))
		return TRUE
	if(stat & (BROKEN | NOPOWER))
		to_chat(user, span_warning("The furnace has no power or requires repairs."))
		return TRUE
	firing = TRUE
	icon_state = "nt_cruciforge_work"
	var/ignition_energy = use_power_oneoff(active_power_usage * 6)
	chamber_air.add_thermal_energy(ignition_energy)
	for(var/step in 1 to 3)
		chamber_air.react()
	set_light(3, 3, "#ff7b22")
	visible_message(span_notice("[src] seals its chamber and begins heating the charge."))
	firing_timer = addtimer(CALLBACK(src, PROC_REF(finish_firing)), 6 SECONDS, TIMER_STOPPABLE)
	return TRUE

/obj/machinery/material_furnace/verb/eject_contents()
	set name = "Eject contents"
	set category = "Object"
	set src in oview(1)

	if(firing)
		to_chat(usr, span_warning("The sealed furnace cannot be opened while firing."))
		return
	if(!output_stock && !LAZYLEN(feedstock) && !LAZYLEN(carbon_feed))
		to_chat(usr, span_notice("The furnace is empty."))
		return
	usr.visible_message(
		span_notice("[usr] begins opening [src]."),
		span_notice("You begin opening [src].")
	)
	if(!do_after(usr, 1 SECOND, target = src) || firing)
		return
	if(output_stock)
		var/obj/item/stack/material/processed_alloy/finished = output_stock
		output_stock = null
		finished.forceMove(usr.drop_location())
		usr.put_in_hands(finished)
		usr.visible_message(
			span_notice("[usr] removes [finished] from [src]'s output tray."),
			span_notice("You remove [finished] from [src]'s output tray.")
		)
	if(LAZYLEN(feedstock) || LAZYLEN(carbon_feed))
		unload_charge(usr)

/obj/machinery/material_furnace/proc/finish_firing()
	firing_timer = null
	firing = FALSE
	icon_state = "nt_cruciforge"
	set_light(0)
	var/datum/material_batch/batch
	var/heat_treatment = FALSE
	if(LAZYLEN(feedstock) == 1 && !LAZYLEN(carbon_feed) && !reagents?.total_volume)
		var/obj/item/stack/material/processed_alloy/existing_stock = feedstock[1]
		if(istype(existing_stock) && istype(existing_stock.material, /datum/material/processed_alloy))
			heat_treatment = TRUE
			batch = existing_stock.physical_batch().copy_batch()
			qdel(existing_stock)
	if(!batch)
		batch = new
	for(var/obj/item/stack/material/stock as anything in feedstock)
		if(QDELETED(stock))
			continue
		while(stock && stock.get_amount() && batch.amount < MATERIAL_SCIENCE_MAX_BATCH)
			material_batch_absorb_sheet(batch, stock)
		if(!QDELETED(stock) && stock.get_amount())
			stock.forceMove(get_turf(src))
	feedstock = null
	for(var/obj/item/ore/coal in carbon_feed)
		batch.add_additive("carbon", 4, 0.5, MATERIAL_COST_CHEMICALS)
		qdel(coal)
	carbon_feed = null
	if(!batch.amount)
		qdel(batch)
		return
	process_chemistry(batch)
	apply_real_atmosphere(batch)
	var/chamber_temperature = chamber_air.return_temperature()
	if(chamber_temperature > batch.temperature)
		batch.add_thermal_energy((chamber_temperature - batch.temperature) * batch.thermal_capacity())
	var/target_temperature = batch.melting_temperature() * (heat_treatment ? 0.7 : 1.05)
	var/heating_energy = max(0, target_temperature - batch.temperature) * batch.thermal_capacity()
	var/supplied_energy = use_power_oneoff(heating_energy)
	batch.add_thermal_energy(supplied_energy)
	batch.record_electricity(supplied_energy)
	if(heat_treatment && batch.phase == MATERIAL_PHASE_SOLID)
		if(!batch.apply_process(MATERIAL_PROCESS_SOLUTION_TREAT))
			visible_message(span_warning("[src] could not complete the heat treatment. The stock remains recoverable."))
			output_stock = processed_spawn_stack(get_turf(src), batch, batch.amount)
			qdel(batch)
			return
	else
		if(!batch.apply_process(MATERIAL_PROCESS_MELT) || !batch.apply_process(MATERIAL_PROCESS_HOMOGENIZE) || !batch.apply_process(MATERIAL_PROCESS_CAST))
			visible_message(span_warning("[src] could not fully melt and combine the charge. The material remains recoverable."))
			output_stock = processed_spawn_stack(get_turf(src), batch, batch.amount)
			qdel(batch)
			return
	output_stock = processed_spawn_stack(get_turf(src), batch, max(1, round(batch.amount * batch.yield_fraction)))
	if(output_stock)
		output_stock.forceMove(src)
	visible_message(span_notice("[src] finishes firing. The completed alloy is ready to collect."))
	qdel(batch)

/obj/machinery/material_furnace/proc/process_chemistry(datum/material_batch/batch)
	if(!reagents?.total_volume)
		return
	var/acid = reagents.get_reagent_amount(REAGENT_ID_SACID) + reagents.get_reagent_amount(REAGENT_ID_PACID)
	var/carbon = reagents.get_reagent_amount(REAGENT_ID_CARBON)
	var/silicon = reagents.get_reagent_amount(REAGENT_ID_SILICON)
	var/lithium = reagents.get_reagent_amount(REAGENT_ID_LITHIUM)
	var/coolant = reagents.get_reagent_amount(REAGENT_ID_COOLANT)
	var/frost_oil = reagents.get_reagent_amount(REAGENT_ID_FROSTOIL)
	if(carbon) batch.add_additive("carbon", min(carbon, 8), 1, MATERIAL_COST_CHEMICALS)
	if(silicon) batch.add_additive("silicon", min(silicon, 6), 1, MATERIAL_COST_CHEMICALS)
	if(lithium >= 2) batch.add_additive("conductive dopant", min(lithium, 6), 2, MATERIAL_COST_CHEMICALS)
	if(coolant >= 2) batch.add_additive("thermal phase catalyst", min(coolant, 6), 2, MATERIAL_COST_CHEMICALS)
	if(frost_oil >= 2) batch.add_additive("cryogenic stabilizer", min(frost_oil, 6), 2, MATERIAL_COST_CHEMICALS)
	if(acid >= 5)
		batch.purity = clamp(batch.purity + min(round(acid / 2), 12), 0, 100)
	for(var/datum/reagent/reagent in reagents.reagent_list)
		if(!(reagent.id in list(REAGENT_ID_CARBON, REAGENT_ID_SILICON, REAGENT_ID_LITHIUM, REAGENT_ID_COOLANT, REAGENT_ID_FROSTOIL, REAGENT_ID_SACID, REAGENT_ID_PACID)))
			batch.add_additive(reagent.name, min(reagent.volume, 6), max(reagent.supply_conversion_value, 0.05), MATERIAL_COST_CHEMICALS)
	LAZYADD(batch.process_history, "chemically treated in [round(reagents.total_volume, 0.1)]u medium")
	reagents.clear_reagents()

/obj/machinery/material_furnace/proc/apply_real_atmosphere(datum/material_batch/batch)
	var/pressure = chamber_air.return_pressure()
	if(pressure < 20)
		batch.atmosphere = MATERIAL_ATMOSPHERE_VACUUM
		batch.purity = clamp(batch.purity + 3, 0, 100)
		batch.porosity = clamp(batch.porosity - 4, 0, 100)
	var/hydrogen = chamber_air.get_moles(/datum/gas/hydrogen)
	if(hydrogen > 0.05)
		var/used = min(hydrogen, 0.08 * clamp(pressure / ONE_ATMOSPHERE, 0, 5))
		batch.atmosphere = MATERIAL_ATMOSPHERE_REDUCING
		batch.add_dissolved_gas("hydrogen", used * 25)
		chamber_air.adjust_moles(/datum/gas/hydrogen, -used)
	var/phoron = chamber_air.get_moles(/datum/gas/plasma)
	if(phoron > 0.05)
		var/used = min(phoron, 0.025)
		batch.add_dissolved_gas("phoron", used * 40)
		batch.add_additive("phoron interstitial", used * 20, 3, MATERIAL_COST_CHEMICALS)
		chamber_air.adjust_moles(/datum/gas/plasma, -used)
	batch.recalculate()

/obj/machinery/material_furnace/proc/unload_charge(mob/user)
	if(firing || output_stock)
		return FALSE
	for(var/obj/item/stack/material/stock as anything in feedstock)
		stock.forceMove(user.drop_location())
	feedstock = null
	for(var/obj/item/ore/coal as anything in carbon_feed)
		coal.forceMove(user.drop_location())
	carbon_feed = null
	visible_message(span_notice("[user] unloads the unfired charge from [src]."))
	return TRUE

/obj/structure/material_anvil
	name = "materials anvil"
	desc = "A heavy anvil for forging hot alloy stock. Place an alloy on it, then strike it with a hammer."
	icon = 'icons/obj/props/fantasy.dmi'
	icon_state = "anvil"
	anchored = TRUE
	density = TRUE
	var/obj/item/stack/material/processed_alloy/stock

/obj/structure/material_anvil/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/stack/material/processed_alloy))
		if(stock)
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		stock = item
		return
	if(istype(item, /obj/item/melee/hammer) && stock)
		var/datum/material_batch/batch = stock.physical_batch().copy_batch()
		if(!batch.apply_process(MATERIAL_PROCESS_FORGE))
			to_chat(user, span_warning("The stock is outside its forging range; heat it in the alloy furnace first."))
			qdel(batch)
			return
		var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, src)
		stock = replacement
		stock.forceMove(src)
		qdel(batch)
		visible_message(span_notice("[user] works the alloy under the hammer, refining its shape and internal structure."))
		return
	return ..()

/obj/structure/material_anvil/attack_hand(mob/user)
	if(!stock)
		return ..()
	stock.forceMove(get_turf(src))
	stock = null
	return TRUE

/obj/structure/bed/bath/material_treatment
	name = "material treatment bath"
	desc = "A treatment bath for quenching hot alloys or cleaning them with acid. Fill it with a suitable liquid, then apply the alloy stock."
	icon_state = "bath_off"
	anchored = TRUE

/obj/structure/bed/bath/material_treatment/Initialize(mapload)
	. = ..()
	create_reagents(200)

/obj/structure/bed/bath/material_treatment/attackby(obj/item/item, mob/user)
	if(!istype(item, /obj/item/stack/material/processed_alloy))
		return ..()
	if(!reagents?.total_volume)
		to_chat(user, span_warning("The bath contains no treatment medium."))
		return
	var/obj/item/stack/material/processed_alloy/stock = item
	var/datum/material_batch/batch = stock.physical_batch().copy_batch()
	var/required_medium = max(2, stock.get_amount() * 2)
	if(reagents.total_volume < required_medium)
		to_chat(user, span_warning("Treating [stock.get_amount()] sheets requires at least [required_medium] units of medium."))
		qdel(batch)
		return
	var/acid = reagents.get_reagent_amount(REAGENT_ID_SACID) + reagents.get_reagent_amount(REAGENT_ID_PACID)
	var/process_succeeded
	var/process_description
	if(acid >= required_medium * 0.5)
		process_succeeded = batch.apply_process(MATERIAL_PROCESS_PURIFY)
		process_description = "acid-cleans"
	else
		var/quench_option = "water"
		if(reagents.get_reagent_amount(REAGENT_ID_FROSTOIL) + reagents.get_reagent_amount(REAGENT_ID_COOLANT) >= required_medium * 0.5)
			quench_option = "cryo"
		else if(reagents.get_reagent_amount(REAGENT_ID_OIL) + reagents.get_reagent_amount(REAGENT_ID_COOKINGOIL) >= required_medium * 0.5)
			quench_option = "oil"
		process_succeeded = batch.apply_process(MATERIAL_PROCESS_QUENCH, quench_option)
		process_description = "[quench_option]-quenches"
	if(!process_succeeded)
		to_chat(user, span_warning("The stock is not hot and solution-treated enough to quench. Heat-treat it in the alloy furnace first."))
		qdel(batch)
		return
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, user.drop_location())
	user.put_in_hands(replacement)
	reagents.remove_any(required_medium)
	qdel(batch)
	visible_message(span_notice("[user] [process_description] [stock] in [src]."))

/obj/item/stack/material/processed_alloy/attackby(obj/item/item, mob/user)
	if(!istype(material, /datum/material/processed_alloy))
		return ..()
	var/datum/material_batch/batch = physical_batch().copy_batch()
	var/changed = FALSE
	if(istype(item, /obj/item/slime_extract))
		var/obj/item/slime_extract/extract = item
		if(!extract.uses)
			qdel(batch)
			return ..()
		var/layer
		if(istype(extract, /obj/item/slime_extract/blue))
			layer = MATERIAL_SURFACE_SLIME_CRYO
		else if(istype(extract, /obj/item/slime_extract/yellow))
			layer = MATERIAL_SURFACE_SLIME_CONDUCTIVE
		else if(istype(extract, /obj/item/slime_extract/orange))
			layer = MATERIAL_SURFACE_SLIME_THERMAL
		else if(istype(extract, /obj/item/slime_extract/purple))
			layer = MATERIAL_SURFACE_SLIME_CATALYTIC
		else if(istype(extract, /obj/item/slime_extract/silver))
			layer = MATERIAL_SURFACE_SLIME_CORROSION
		else if(istype(extract, /obj/item/slime_extract/metal))
			layer = MATERIAL_SURFACE_SLIME_METAL
		else if(istype(extract, /obj/item/slime_extract/bluespace))
			layer = MATERIAL_SURFACE_SLIME_BLUESPACE
		else
			to_chat(user, span_warning("[extract] cannot form a stable engineering surface on this stock."))
			qdel(batch)
			return ..()
		batch.add_surface_layer(layer, 35, "[extract.name] matrix", 4)
		extract.uses--
		changed = TRUE
	else if(istype(item, /obj/item/ore/coal))
		batch.add_surface_layer(MATERIAL_SURFACE_CARBON, 35, "carbon", 3)
		qdel(item)
		changed = TRUE
	else if(istype(item, /obj/item/analyzer))
		to_chat(user, span_notice("Composition [json_encode(batch.composition)]; purity [batch.purity]%; conductivity [batch.conductivity]%; hardness [batch.hardness]."))
		var/list/certification = batch.evidence_context("physical analyzer assay")
		certification["amount"] = get_amount()
		ensure_feedstock_lot()
		certification["material_lot_id"] = feedstock_lot_id
		certification["actor_account"] = contract_account_for_mob(user)?.account_number
		emit_contract_event(CONTRACT_EVENT_MATERIAL_CERTIFIED, certification, "material-certification:[REF(src)]:[world.time]", src, user)
		to_chat(user, span_notice("The analyzer records a traceable qualification for batch [copytext(batch.fingerprint(), 1, 9)]."))
	else if(item.has_tool_quality(TOOL_MULTITOOL))
		to_chat(user, span_notice("The stock measures [batch.conductivity]% relative conductivity and [batch.homogeneity]% lattice order."))
	if(changed)
		var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(src, batch, user.drop_location())
		user.put_in_hands(replacement)
	qdel(batch)
	if(changed)
		return
	return ..()

/// Emitter fire is the accessible pulse-treatment route. Receptive crystal
/// lattices retain part of the shot; ordinary stock simply becomes hot.
/obj/item/stack/material/processed_alloy/bullet_act(obj/item/projectile/projectile, def_zone)
	if(!istype(projectile, /obj/item/projectile/beam/emitter))
		return ..()
	var/datum/material_batch/batch = physical_batch()?.copy_batch()
	if(!batch)
		return ..()
	var/beam_energy = max(projectile.damage, 1) * 100
	batch.add_thermal_energy(beam_energy * 0.65)
	batch.record_electricity(beam_energy)
	var/crystal_fraction = ((LAZYACCESS(batch.composition, MAT_GLASS) || 0) + (LAZYACCESS(batch.composition, MAT_QUARTZ) || 0) + (LAZYACCESS(batch.composition, MAT_DIAMOND) || 0) + (LAZYACCESS(batch.composition, MAT_VOLTAIC_CRYSTAL) || 0)) / max(batch.amount, 1)
	if(crystal_fraction >= 0.1 && batch.conductivity >= 25)
		var/strength = clamp(round(projectile.damage / 5), 2, 20)
		batch.add_field_treatment(MATERIAL_FIELD_EMITTER, strength)
		batch.add_field_treatment(MATERIAL_FIELD_ENERGY_STORAGE, round(strength * crystal_fraction))
		visible_message(span_notice("[src] catches the beam in a bright internal lattice; light continues to crawl through it after the shot."))
	else
		visible_message(span_warning("[src] flashes red-hot under the emitter beam."))
	var/old_pixel_x = pixel_x
	var/old_pixel_y = pixel_y
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(src, batch, get_turf(src))
	if(replacement)
		replacement.pixel_x = old_pixel_x
		replacement.pixel_y = old_pixel_y
	qdel(batch)
	return 0

/obj/machinery/particle_smasher/proc/try_material_stock_conditioning()
	if(energy < 350 || !istype(target, /obj/item/stack/material/processed_alloy))
		return FALSE
	var/obj/item/stack/material/processed_alloy/stock = target
	var/datum/material_batch/batch = stock.physical_batch().copy_batch()
	var/strength = clamp(round(energy / 20), 10, 60)
	batch.add_field_treatment(MATERIAL_FIELD_PARTICLE, strength)
	var/crystal_fraction = ((LAZYACCESS(batch.composition, MAT_GLASS) || 0) + (LAZYACCESS(batch.composition, MAT_QUARTZ) || 0) + (LAZYACCESS(batch.composition, MAT_DIAMOND) || 0) + (LAZYACCESS(batch.composition, MAT_VOLTAIC_CRYSTAL) || 0) + (LAZYACCESS(batch.composition, MAT_LUMEN_CRYSTAL) || 0)) / max(batch.amount, 1)
	if(crystal_fraction >= 0.1 && batch.conductivity >= 25)
		batch.add_field_treatment(MATERIAL_FIELD_ENERGY_STORAGE, round(strength * crystal_fraction))
	if(batch.hardness >= 45 && batch.toughness >= 45)
		batch.add_field_treatment(MATERIAL_FIELD_RADIATION_HARDENED, round(strength * 0.6))
		batch.structure[MATERIAL_STRUCTURE_DEFECT] = max(0, batch.structure[MATERIAL_STRUCTURE_DEFECT] - round(strength / 10))
	batch.homogeneity = clamp(batch.homogeneity + round(strength / 8), 0, 100)
	batch.record_electricity(300)
	batch.recalculate()
	target = replace_processed_stack(stock, batch, src)
	energy = max(0, energy - 300)
	qdel(batch)
	return TRUE

/obj/item/circuitboard/machine/material_furnace
	name = T_BOARD("controlled-atmosphere alloy furnace")
	build_path = /obj/machinery/material_furnace
	board_type = new /datum/frame/frame_types/machine
	req_components = list(/obj/item/stock_parts/matter_bin = 2, /obj/item/stock_parts/manipulator = 1, /obj/item/stock_parts/micro_laser = 2)

/datum/design_techweb/board/material_furnace
	SET_CIRCUIT_DESIGN_NAMEDESC("controlled-atmosphere alloy furnace")
	id = "board_material_furnace"
	build_path = /obj/item/circuitboard/machine/material_furnace
	category = list(RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_MACHINE_RESEARCH)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_ENGINEERING

/datum/techweb_node/material_processing
	id = "material_processing"
	display_name = "Advanced Material Processing"
	description = "Controlled alloying, heat treatment, and physical material characterization."
	starting_node = TRUE
	design_ids = list("board_material_furnace")

/// Applies production treatments instantly for isolated testing. The target is
/// still replaced through the normal processed-stack path, exercising material
/// registration and every downstream consumer exactly as gameplay does.
ADMIN_VERB(debug_apply_material_treatment, R_DEBUG, "Apply Material Treatment", "Apply a material treatment to held or nearby alloy sheets for testing.", ADMIN_CATEGORY_DEBUG_GAME)
	var/static/list/treatments = list(
		"Particle conditioned" = MATERIAL_FIELD_PARTICLE,
		"Magnetically aligned" = MATERIAL_FIELD_MAGNETIC,
		"Emitter charged" = MATERIAL_FIELD_EMITTER,
		"Fusion stabilized" = MATERIAL_FIELD_FUSION,
		"Radiation hardened" = MATERIAL_FIELD_RADIATION_HARDENED,
		"Field-energy storage" = MATERIAL_FIELD_ENERGY_STORAGE,
		"Carbon coating" = MATERIAL_SURFACE_CARBON,
		"Metal slime coating" = MATERIAL_SURFACE_SLIME_METAL,
		"Cryogenic slime coating" = MATERIAL_SURFACE_SLIME_CRYO,
		"Thermal slime coating" = MATERIAL_SURFACE_SLIME_THERMAL,
		"Conductive slime coating" = MATERIAL_SURFACE_SLIME_CONDUCTIVE,
		"Corrosion-resistant slime coating" = MATERIAL_SURFACE_SLIME_CORROSION,
		"Catalytic slime coating" = MATERIAL_SURFACE_SLIME_CATALYTIC,
		"Bluespace slime coating" = MATERIAL_SURFACE_SLIME_BLUESPACE,
	)
	var/mob/operator = user.mob
	if(!operator)
		return
	var/obj/item/stack/material/processed_alloy/stock = operator.get_active_hand()
	if(!istype(stock))
		var/list/nearby_stock = list()
		for(var/obj/item/stack/material/processed_alloy/candidate in view(operator))
			nearby_stock += candidate
		if(!length(nearby_stock))
			to_chat(operator, span_warning("Hold alloy sheets in your active hand or stand near a stack."))
			return
		stock = tgui_input_list(operator, "Choose nearby alloy sheets.", "Material Treatment", nearby_stock)
	var/selection = tgui_input_list(operator, "Choose a treatment to apply at full test strength.", "Material Treatment", treatments)
	if(!selection || QDELETED(stock) || !operator.Adjacent(stock))
		return
	var/datum/material_batch/batch = stock.physical_batch()?.copy_batch()
	if(!batch)
		return
	var/treatment = treatments[selection]
	if(findtext(treatment, "lattice") || (treatment in list(MATERIAL_FIELD_RADIATION_HARDENED, MATERIAL_FIELD_ENERGY_STORAGE)))
		batch.add_field_treatment(treatment, 100)
	else
		batch.add_surface_layer(treatment, 100, "debug treatment", 0)
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, operator.drop_location())
	qdel(batch)
	if(replacement)
		operator.put_in_hands(replacement)
		to_chat(operator, span_notice("Applied [lowertext(selection)] to [replacement]."))
