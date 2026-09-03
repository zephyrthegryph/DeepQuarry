/// Physical material workshop. Inputs and outputs are always ordinary material
/// stacks; machines never expose a bespoke batch carrier or workpiece item.

/datum/material_batch/proc/dominant_color()
	var/datum/material/dominant
	var/dominant_amount = 0
	for(var/material_name in composition)
		if(composition[material_name] > dominant_amount)
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

/proc/replace_processed_stack(obj/item/stack/material/old_stock, datum/material_batch/new_batch, atom/location)
	if(!istype(old_stock) || !istype(new_batch))
		return null
	var/amount = old_stock.get_amount()
	var/obj/item/stack/material/processed_alloy/replacement = processed_spawn_stack(get_turf(location || old_stock), new_batch, amount)
	qdel(old_stock)
	return replacement

/obj/machinery/material_furnace
	name = "controlled-atmosphere alloy furnace"
	desc = "A general alloy furnace. Load ordinary material stacks and chemical media directly; it returns ordinary processed stock."
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
		. += span_notice("Finished stock is waiting in the output cradle.")
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
		visible_message(span_notice("[user] loads [stock] directly into [src]."))
		return
	if(istype(item, /obj/item/ore/coal))
		if(firing || output_stock)
			return
		user.drop_from_inventory(item)
		item.forceMove(src)
		LAZYADD(carbon_feed, item)
		visible_message(span_notice("[user] packs carbon feed around the loaded stock."))
		return
	if(istype(item, /obj/item/tank))
		if(firing)
			return
		var/obj/item/tank/tank = item
		var/datum/gas_mixture/charge = tank.air_contents?.remove(5)
		if(charge)
			chamber_air.merge(charge)
			qdel(charge)
			visible_message(span_notice("[user] meters gas from [tank] into the furnace atmosphere."))
		return
	if(istype(item, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/container = item
		if(container.reagents?.total_volume)
			var/transferred = container.reagents.trans_to(src, min(10, container.reagents.total_volume))
			if(transferred)
				to_chat(user, span_notice("You add [round(transferred, 0.1)]u of chemical medium directly to the furnace."))
				return
	return ..()

/obj/machinery/material_furnace/attack_hand(mob/user)
	if(..())
		return TRUE
	if(firing || output_stock || !LAZYLEN(feedstock) || (stat & (BROKEN | NOPOWER)))
		to_chat(user, span_warning("The furnace cannot begin a firing."))
		return TRUE
	firing = TRUE
	icon_state = "nt_cruciforge_work"
	use_power(active_power_usage * 6)
	chamber_air.add_thermal_energy(active_power_usage * 6)
	for(var/step in 1 to 3)
		chamber_air.react()
	set_light(3, 3, "#ff7b22")
	visible_message(span_notice("[src] seals around the physical stock and blooms with visible heat."))
	firing_timer = addtimer(CALLBACK(src, PROC_REF(finish_firing)), 6 SECONDS, TIMER_STOPPABLE)
	return TRUE

/obj/machinery/material_furnace/proc/finish_firing()
	firing_timer = null
	firing = FALSE
	icon_state = "nt_cruciforge"
	set_light(0)
	var/datum/material_batch/batch = new
	for(var/obj/item/stack/material/stock as anything in feedstock)
		while(stock && stock.get_amount() && batch.amount < MATERIAL_SCIENCE_MAX_BATCH)
			material_batch_absorb_sheet(batch, stock)
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
	batch.temperature = max(batch.temperature, chamber_temperature)
	if(batch.can_process(MATERIAL_PROCESS_MELT))
		batch.apply_process(MATERIAL_PROCESS_MELT)
	if(batch.phase == MATERIAL_PHASE_MOLTEN)
		batch.apply_process(MATERIAL_PROCESS_HOMOGENIZE)
		batch.apply_process(MATERIAL_PROCESS_CAST)
	batch.temperature = T20C
	output_stock = processed_spawn_stack(get_turf(src), batch, max(1, round(batch.amount * batch.yield_fraction)))
	if(output_stock)
		output_stock.forceMove(src)
	visible_message(span_notice("[src] opens; an ordinary stack of visibly alloyed stock rests in its output cradle."))
	qdel(batch)

/obj/machinery/material_furnace/proc/process_chemistry(datum/material_batch/batch)
	if(!reagents?.total_volume)
		return
	var/acid = reagents.get_reagent_amount(REAGENT_ID_SACID) + reagents.get_reagent_amount(REAGENT_ID_PACID)
	var/carbon = reagents.get_reagent_amount(REAGENT_ID_CARBON)
	var/silicon = reagents.get_reagent_amount(REAGENT_ID_SILICON)
	if(carbon) batch.add_additive("carbon", min(carbon, 8), 1, MATERIAL_COST_CHEMICALS)
	if(silicon) batch.add_additive("silicon", min(silicon, 6), 1, MATERIAL_COST_CHEMICALS)
	if(acid >= 5)
		batch.purity = clamp(batch.purity + min(round(acid / 2), 12), 0, 100)
	for(var/datum/reagent/reagent in reagents.reagent_list)
		if(!(reagent.id in list(REAGENT_ID_CARBON, REAGENT_ID_SILICON, REAGENT_ID_SACID, REAGENT_ID_PACID)))
			batch.add_additive(reagent.name, min(reagent.volume, 6), max(reagent.supply_conversion_value, 0.05), MATERIAL_COST_CHEMICALS)
	batch.process_history += "chemically treated in [round(reagents.total_volume, 0.1)]u medium"
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

/obj/machinery/material_furnace/crowbar_act(mob/user, obj/item/tool)
	if(firing)
		return ..()
	if(output_stock)
		output_stock.forceMove(get_turf(src))
		output_stock = null
		return ITEM_INTERACT_SUCCESS
	for(var/obj/item/stack/material/stock as anything in feedstock)
		stock.forceMove(get_turf(src))
	feedstock = null
	return ITEM_INTERACT_SUCCESS

/obj/structure/material_anvil
	name = "materials anvil"
	desc = "An anvil that forges ordinary processed-material stacks directly."
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
		var/datum/material/processed_alloy/material = stock.material
		var/datum/material_batch/batch = material.batch_template.copy_batch()
		batch.temperature = max(batch.temperature, T0C + 300)
		batch.apply_process(MATERIAL_PROCESS_FORGE)
		var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, src)
		stock = replacement
		stock.forceMove(src)
		qdel(batch)
		visible_message(span_notice("[user] forges the stock; its grain and surface visibly change under the hammer."))
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
	desc = "A general treatment bath. Apply ordinary processed stock directly to quench or chemically treat it."
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
	var/datum/material/processed_alloy/material = stock.material
	var/datum/material_batch/batch = material.batch_template.copy_batch()
	var/acid = reagents.get_reagent_amount(REAGENT_ID_SACID) + reagents.get_reagent_amount(REAGENT_ID_PACID)
	if(acid)
		batch.purity = clamp(batch.purity + min(round(acid / 2), 12), 0, 100)
		batch.apply_process(MATERIAL_PROCESS_PURIFY)
	else
		batch.temperature = max(batch.temperature, T0C + 500)
		batch.apply_process(MATERIAL_PROCESS_QUENCH)
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, user.drop_location())
	user.put_in_hands(replacement)
	reagents.remove_any(min(10, reagents.total_volume))
	qdel(batch)
	visible_message(span_notice("[user] treats the physical stock in [src]; its surface and grain visibly change."))

/obj/item/stack/material/processed_alloy/attackby(obj/item/item, mob/user)
	if(!istype(material, /datum/material/processed_alloy))
		return ..()
	var/datum/material/processed_alloy/processed = material
	var/datum/material_batch/batch = processed.batch_template.copy_batch()
	var/changed = FALSE
	if(istype(item, /obj/item/slime_extract))
		var/obj/item/slime_extract/extract = item
		if(!extract.uses)
			qdel(batch)
			return ..()
		var/layer = istype(extract, /obj/item/slime_extract/blue) ? MATERIAL_SURFACE_SLIME_CRYO : istype(extract, /obj/item/slime_extract/yellow) ? MATERIAL_SURFACE_SLIME_CONDUCTIVE : "[extract.name] bonded surface"
		batch.add_surface_layer(layer, 35, "[extract.name] matrix", 4)
		extract.uses--
		changed = TRUE
	else if(istype(item, /obj/item/ore/coal))
		batch.add_surface_layer(MATERIAL_SURFACE_CARBON, 35, "carbon", 3)
		qdel(item)
		changed = TRUE
	else if(item.type == /obj/item/analyzer)
		to_chat(user, span_notice("Composition [json_encode(batch.composition)]; purity [batch.purity]%; conductivity [batch.conductivity]%; hardness [batch.hardness]."))
	else if(istype(item, /obj/item/multitool))
		to_chat(user, span_notice("The stock measures [batch.conductivity]% relative conductivity and [batch.homogeneity]% lattice order."))
	if(changed)
		var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(src, batch, user.drop_location())
		user.put_in_hands(replacement)
	qdel(batch)
	if(changed)
		return
	return ..()

/obj/machinery/particle_smasher/proc/try_material_stock_conditioning()
	if(energy < 350 || !istype(target, /obj/item/stack/material/processed_alloy))
		return FALSE
	var/obj/item/stack/material/processed_alloy/stock = target
	var/datum/material/processed_alloy/material = stock.material
	var/datum/material_batch/batch = material.batch_template.copy_batch()
	var/strength = clamp(round(energy / 20), 10, 60)
	batch.add_field_treatment(MATERIAL_FIELD_PARTICLE, strength)
	batch.homogeneity = clamp(batch.homogeneity + round(strength / 8), 0, 100)
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
