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
	replaced_by(old_stock, replacement)
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
	var/tmp/obj/item/stack/material/processed_alloy/output_stock
	var/firing = FALSE
	var/datum/gas_mixture/chamber_air

// The unfired charge sits in the furnace's contents until it is fired or unloaded.
/obj/machinery/material_furnace/ownership()
	. = ..()
	. += owns(nameof(feedstock), policy = OWN_CONTAINED, is_list = TRUE)
	. += owns(nameof(carbon_feed), policy = OWN_CONTAINED, is_list = TRUE)

CAPABILITIES(/obj/machinery/material_furnace)
	reagents(120)
	owns_one(nameof(chamber_air), /datum/gas_mixture)

DECLARE_GAS(/obj/machinery/material_furnace, "chamber_air", 500, T20C, null)

// ALLOW(init/INSTANCE_STATE): copies the build turf's air into this instance's chamber
/obj/machinery/material_furnace/Initialize(mapload)
	. = ..()
	var/turf/furnace_turf = get_turf(src)
	var/datum/gas_mixture/environment = furnace_turf?.return_air()
	if(environment)
		chamber_air.copy_from(environment)


/obj/machinery/material_furnace/examine(mob/user)
	. = ..()
	. += span_notice("Loaded stock: [LAZYLEN(feedstock)] stack(s); chemical medium: [round(reagents?.total_volume || 0, 0.1)]u.")
	if(output_stock())
		. += span_notice("Finished alloy is ready. Click the furnace to collect it.")
	else if(LAZYLEN(feedstock))
		. += span_notice("The charge is ready. Click to fire it, or use Eject contents to unload it.")
	if(chamber_air)
		. += span_notice("Chamber: [round(chamber_air.return_pressure(), 0.1)] kPa at [round(chamber_air.return_temperature(), 0.1)] K.")

EXTEND_INTERACTIONS(/obj/machinery/material_furnace, \
	INTERACT_INSERT(/obj/item/stack/material, PROC_REF(interaction_load_stock), "Load material", REQ_TARGET_STATE(/obj/machinery/material_furnace/proc/can_load_stock)), \
	INTERACT_INSERT(/obj/item/ore/coal, PROC_REF(interaction_load_carbon), "Add carbon"), \
	INTERACT_INSERT(/obj/item/tank, PROC_REF(interaction_transfer_gas), "Transfer gas"), \
	INTERACT_INSERT(/obj/item/reagent_containers, PROC_REF(interaction_transfer_reagents), "Pour"), \
	INTERACT_VERB("Eject contents", PROC_REF(interaction_eject_contents), REQ_FIELD_NOT("firing", "the sealed furnace can't be opened while firing"), REQ_TARGET_STATE(/obj/machinery/material_furnace/proc/can_eject_contents)), \
	INTERACT_HAND("Use", PROC_REF(interaction_use), REQ_TARGET_STATE(/obj/machinery/material_furnace/proc/can_use_furnace)), \
)

/// Requirement: TRUE, or why this stack can't be loaded now.
/obj/machinery/material_furnace/proc/can_load_stock(mob/user, atom/target, obj/item/stack/material/held)
	if(firing || output_stock())
		return "the furnace must be idle and its output removed first"
	if(istype(held) && held.uses_charge)
		return "[held] is drawn from a matter synthesiser and can't be charged into the furnace as physical stock"
	return TRUE

/obj/machinery/material_furnace/proc/interaction_load_stock(mob/user, obj/item/stack/material/stock, datum/interaction/interaction)
	if(!move_into(src, nameof(src.feedstock), stock, user)) // the user is told why
		return TRUE
	act_message(user, src, others = span_notice("%U% loads [stock] into %T%."))
	return TRUE

/obj/machinery/material_furnace/proc/interaction_load_carbon(mob/user, obj/item/item, datum/interaction/interaction)
	if(firing || output_stock())
		return TRUE
	if(!move_into(src, nameof(src.carbon_feed), item, user)) // the user is told why
		return TRUE
	act_message(user, src, others = span_notice("%U% adds carbon to %T%'s charge."))
	return TRUE

/obj/machinery/material_furnace/proc/interaction_transfer_gas(mob/user, obj/item/tank/tank, datum/interaction/interaction)
	if(firing)
		return TRUE
	var/from_tank = tank.air_contents?.return_pressure() > chamber_air.return_pressure()
	var/datum/gas_mixture/charge = from_tank ? tank.air_contents?.remove(5) : chamber_air.remove(5)
	if(charge)
		if(from_tank)
			chamber_air.merge(charge)
		else
			tank.air_contents.merge(charge)
		consumed(charge, src)
		act_message(user, src, others = span_notice("%U% transfers gas [from_tank ? "from [tank] into" : "from %T% into"] the furnace chamber."))
	return TRUE

/obj/machinery/material_furnace/proc/interaction_transfer_reagents(mob/user, obj/item/reagent_containers/container, datum/interaction/interaction)
	if(container.reagents?.total_volume)
		var/transferred = container.reagents.trans_to(src, min(10, container.reagents.total_volume))
		if(transferred)
			to_chat(user, span_notice("You pour [round(transferred, 0.1)] units from [container] into the furnace chamber."))
			return TRUE
	return FALSE

/// Requirement: TRUE when there is output to take or a charge that can be fired, else why not.
/obj/machinery/material_furnace/proc/can_use_furnace(mob/user, atom/target, obj/item/held)
	if(output_stock() && !firing)
		return TRUE
	if(firing)
		return "the furnace is still firing"
	if(!LAZYLEN(feedstock))
		return "the furnace is empty; load material sheets before firing it"
	if(!operable())
		return "the furnace has no power or requires repairs"
	return TRUE

/obj/machinery/material_furnace/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(output_stock() && !firing)
		var/obj/item/stack/material/processed_alloy/finished = output_stock()
		rel_clear(src, nameof(output_stock))
		finished.forceMove(user.drop_location())
		user.put_in_hands(finished)
		act_message(user, src, others = span_notice("%U% removes [finished] from %T%'s output tray."))
		return TRUE
	firing = TRUE
	icon_state = "nt_cruciforge_work"
	var/ignition_energy = use_power_oneoff(active_power_usage * 6)
	heat_add(chamber_air, ignition_energy, HEAT_SOURCE_DEVICE)
	for(var/step in 1 to 3)
		chamber_air.react()
	set_light(3, 3, "#ff7b22")
	visible_message(span_notice("[src] seals its chamber and begins heating the charge."))
	after(src, 6 SECONDS, PROC_REF(finish_firing), key = "firing_timer")
	return TRUE

/// Requirement: TRUE, or why there is nothing to eject.
/obj/machinery/material_furnace/proc/can_eject_contents(mob/user, atom/target, obj/item/held)
	if(!output_stock() && !LAZYLEN(feedstock) && !LAZYLEN(carbon_feed))
		return "the furnace is empty"
	return TRUE

/obj/machinery/material_furnace/proc/interaction_eject_contents(mob/user, obj/item/held, datum/interaction/interaction)
	act_message(user, src, MSG_SELF(span_notice("You begin opening %T%.")), MSG_OTHERS(span_notice("%U% begins opening %T%.")))
	task_timed(user, 1 SECOND, src, src, PROC_REF(eject_contents_done), list(user))
	return TRUE

/obj/machinery/material_furnace/proc/eject_contents_done(mob/user)
	if(firing)
		return
	if(output_stock())
		var/obj/item/stack/material/processed_alloy/finished = output_stock()
		rel_clear(src, nameof(output_stock))
		finished.forceMove(user.drop_location())
		user.put_in_hands(finished)
		act_message(user, src, MSG_SELF(span_notice("You remove [finished] from %T%'s output tray.")), \
			MSG_OTHERS(span_notice("%U% removes [finished] from %T%'s output tray.")))
	if(LAZYLEN(feedstock) || LAZYLEN(carbon_feed))
		unload_charge(user)

/obj/machinery/material_furnace/proc/finish_firing()
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
			consumed(existing_stock, src)
	if(!batch)
		batch = new
	for(var/obj/item/stack/material/stock as anything in feedstock)
		if(QDELETED(stock))
			continue
		while(stock && !QDELETED(stock) && stock.get_amount() && batch.amount < MATERIAL_SCIENCE_MAX_BATCH)
			// absorb_sheet refuses stacks with no material / no sheets; without
			// this break such a stack would spin forever.
			if(!material_batch_absorb_sheet(batch, stock))
				break
		if(!QDELETED(stock) && stock.get_amount())
			stock.forceMove(get_turf(src))
	own_take_all(src, nameof(feedstock))
	for(var/obj/item/ore/coal in carbon_feed)
		batch.add_additive("carbon", 4, 0.5, MATERIAL_COST_CHEMICALS)
		consumed(coal, src)
	own_take_all(src, nameof(carbon_feed))
	if(!batch.amount)
		spent(batch)
		return
	process_chemistry(batch)
	apply_real_atmosphere(batch)
	// A hotter chamber gives the charge what it can: the two meet at their common temperature (it was the chamber's temperature for free).
	if(chamber_air.return_temperature() > batch.temperature())
		heat_equalize(chamber_air, HEAT_STORE(batch.ensure_heat_store()))
	var/target_temperature = batch.melting_temperature() * (heat_treatment ? 0.7 : 1.05)
	var/heating_energy = max(0, target_temperature - batch.temperature()) * batch.thermal_capacity()
	var/supplied_energy = use_power_oneoff(heating_energy)
	batch.add_batch_heat(supplied_energy, HEAT_SOURCE_DEVICE)
	batch.record_electricity(supplied_energy)
	if(heat_treatment && batch.phase == MATERIAL_PHASE_SOLID)
		if(!batch.apply_process(MATERIAL_PROCESS_SOLUTION_TREAT))
			visible_message(span_warning("[src] could not complete the heat treatment. The stock remains recoverable."))
			rel_set(src, nameof(output_stock), processed_spawn_stack(get_turf(src), batch, batch.amount))
			spent(batch)
			return
	else
		if(!batch.apply_process(MATERIAL_PROCESS_MELT) || !batch.apply_process(MATERIAL_PROCESS_HOMOGENIZE) || !batch.apply_process(MATERIAL_PROCESS_CAST))
			visible_message(span_warning("[src] could not fully melt and combine the charge. The material remains recoverable."))
			rel_set(src, nameof(output_stock), processed_spawn_stack(get_turf(src), batch, batch.amount))
			spent(batch)
			return
	rel_set(src, nameof(output_stock), processed_spawn_stack(get_turf(src), batch, max(1, round(batch.amount * batch.yield_fraction))))
	if(output_stock())
		output_stock().forceMove(src)
	visible_message(span_notice("[src] finishes firing. The completed alloy is ready to collect."))
	spent(batch)

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
	if(firing || output_stock())
		return FALSE
	for(var/obj/item/stack/material/stock as anything in feedstock)
		stock.forceMove(user.drop_location())
	own_take_all(src, nameof(feedstock))
	for(var/obj/item/ore/coal as anything in carbon_feed)
		coal.forceMove(user.drop_location())
	own_take_all(src, nameof(carbon_feed))
	act_message(user, src, others = span_notice("%U% unloads the unfired charge from %T%."))
	return TRUE

/obj/structure/material_anvil
	name = "materials anvil"
	desc = "A heavy anvil for forging hot alloy stock. Place an alloy on it, then strike it with a hammer."
	icon = 'icons/obj/props/fantasy.dmi'
	icon_state = "anvil"
	anchored = TRUE
	density = TRUE
	var/tmp/obj/item/stack/material/processed_alloy/stock

/// Old attackby.
/obj/structure/material_anvil/proc/interaction_item(mob/user, obj/item/item, datum/interaction/interaction)
	if(istype(item, /obj/item/stack/material/processed_alloy))
		if(stock())
			to_chat(user, span_warning("There is already stock() on [src]."))
			return INTERACTION_HANDLED_PASS
		var/obj/item/stack/material/processed_alloy/incoming = item
		if(!istype(incoming.material, /datum/material/processed_alloy))
			to_chat(user, span_warning("[incoming] is not processed stock()."))
			return INTERACTION_HANDLED_PASS
		if(!user.drop_from_inventory(incoming))
			return INTERACTION_HANDLED_PASS
		incoming.forceMove(src)
		rel_set(src, nameof(stock), incoming)
		return INTERACTION_HANDLED_PASS
	if(istype(item, /obj/item/melee/hammer) && stock())
		var/datum/material_batch/batch = stock().physical_batch().copy_batch()
		if(!batch.apply_process(MATERIAL_PROCESS_FORGE))
			to_chat(user, span_warning("The stock is outside its forging range; heat it in the alloy furnace first."))
			consumed(batch, src)
			return INTERACTION_HANDLED_PASS
		var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock(), batch, src)
		rel_set(src, nameof(stock), replacement)
		stock().forceMove(src)
		consumed(batch, src)
		act_message(user, null, others = span_notice("%U% works the alloy under the hammer, refining its shape and internal structure."))
		return INTERACTION_HANDLED_PASS
	return FALSE

DECLARE_INTERACTIONS(/obj/structure/material_anvil, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/structure/material_anvil/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!stock())
		return FALSE
	stock().forceMove(get_turf(src))
	rel_clear(src, nameof(stock))
	return TRUE

/obj/structure/bed/bath/material_treatment
	name = "material treatment bath"
	desc = "A treatment bath for quenching hot alloys or cleaning them with acid. Fill it with a suitable liquid, then apply the alloy stock."
	icon_state = "bath_off"
	anchored = TRUE

CAPABILITIES(/obj/structure/bed/bath/material_treatment)
	configure(reagents(volume = 200))

EXTEND_INTERACTIONS(/obj/structure/bed/bath/material_treatment, INTERACT_INSERT(/obj/item/stack/material/processed_alloy, PROC_REF(material_treatment_interaction_item), "Treat alloy", REQ_BECAUSE(REQ_TARGET_STATE(/obj/structure/bed/bath/material_treatment/proc/has_medium), "the bath contains no treatment medium")))

/// Requirement: the bath holds some treatment medium.
/obj/structure/bed/bath/material_treatment/proc/has_medium(mob/user, atom/target, obj/item/held)
	return reagents?.total_volume ? TRUE : FALSE

/// Old attackby.
/obj/structure/bed/bath/material_treatment/proc/material_treatment_interaction_item(mob/user, obj/item/item, datum/interaction/interaction)
	var/obj/item/stack/material/processed_alloy/stock = item
	var/datum/material_batch/batch = stock.physical_batch().copy_batch()
	var/required_medium = max(2, stock.get_amount() * 2)
	if(reagents.total_volume < required_medium)
		to_chat(user, span_warning("Treating [stock.get_amount()] sheets requires at least [required_medium] units of medium."))
		consumed(batch, user)
		return INTERACTION_HANDLED_PASS
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
		consumed(batch, user)
		return INTERACTION_HANDLED_PASS
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, user.drop_location())
	user.put_in_hands(replacement)
	reagents.remove_any(required_medium)
	consumed(batch, user)
	act_message(user, src, others = span_notice("%U% [process_description] [stock] in %T%."))
	return INTERACTION_HANDLED_PASS

/// Old attackby: surface treatments and measurements; anything else falls through as its ..() did.
/obj/item/stack/material/processed_alloy/proc/processed_alloy_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/item = A.held
	if(!istype(material, /datum/material/processed_alloy))
		return OP_DECLINE
	var/datum/material_batch/batch = physical_batch().copy_batch()
	var/changed = FALSE
	if(istype(item, /obj/item/slime_extract))
		var/obj/item/slime_extract/extract = item
		if(!extract.uses)
			spent(batch)
			return OP_DECLINE
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
			spent(batch)
			return OP_DECLINE
		batch.add_surface_layer(layer, 35, "[extract.name] matrix", 4)
		extract.uses--
		changed = TRUE
	else if(istype(item, /obj/item/ore/coal))
		batch.add_surface_layer(MATERIAL_SURFACE_CARBON, 35, "carbon", 3)
		consume(item, user)
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
	spent(batch)
	if(changed)
		return OP_PASS
	return OP_DECLINE

/// Emitter fire is the accessible pulse-treatment route. Receptive crystal
/// lattices retain part of the shot; ordinary stock simply becomes hot.
/obj/item/stack/material/processed_alloy/bullet_act(obj/item/projectile/projectile, def_zone)
	if(!istype(projectile, /obj/item/projectile/beam/emitter))
		return ..()
	var/datum/material_batch/batch = physical_batch()?.copy_batch()
	if(!batch)
		return ..()
	var/beam_energy = max(projectile.damage, 1) * 100
	batch.add_batch_heat(beam_energy * 0.65, HEAT_SOURCE_WEAPON)
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
	destroyed(batch, null, BRUTE)
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
	rel_set(src, nameof(target), replace_processed_stack(stock, batch, src))
	set_energy(max(0, energy - 300))
	spent(batch)
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
	var/mob/operator = user.mob
	if(!operator)
		return
	var/obj/item/stack/material/processed_alloy/stock = operator.get_active_hand()
	if(istype(stock))
		open_treatment(operator)
	else
		var/list/nearby_stock = nearby_choices(operator)
		if(!length(nearby_stock))
			to_chat(operator, span_warning("Hold alloy sheets in your active hand or stand near a stack."))
			return
		open_stock(operator, nearby_stock)

GLOBAL_LIST_INIT(material_debug_treatments, list(
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
))

/datum/admin_verb/debug_apply_material_treatment/proc/nearby_choices(mob/operator)
	var/list/nearby_stock = list()
	for(var/obj/item/stack/material/processed_alloy/candidate in view(operator))
		nearby_stock += candidate
	return nearby_stock

/datum/admin_verb/debug_apply_material_treatment/proc/current_stock(mob/operator, atom/nearby, nearby_answered)
	var/obj/item/stack/material/processed_alloy/stock = operator.get_active_hand()
	if(istype(stock))
		return stock
	return nearby_answered ? nearby : null

/datum/admin_verb/debug_apply_material_treatment/proc/open_stock(mob/operator, list/nearby_stock, selected_treatment)
	open_request(src, /datum/prompt/choice/material_debug_stock, PROC_REF(stock_answered), answerer = operator, choices = nearby_stock, selected_treatment = selected_treatment)

/datum/admin_verb/debug_apply_material_treatment/proc/open_treatment(mob/operator, atom/nearby, nearby_answered = FALSE)
	open_request(src, /datum/prompt/choice/material_debug_treatment, PROC_REF(treatment_answered), answerer = operator, subject = nearby, nearby_answered = nearby_answered, choices = GLOB.material_debug_treatments)

/datum/prompt/choice/material_debug_stock
	rights = R_DEBUG
	timeout = 0
	recheck_on_open = TRUE
	title = "Material Treatment"
	question = "Choose nearby alloy sheets."
	var/selected_treatment

/datum/prompt/choice/material_debug_stock/recheck_extra()
	if(QDELETED(answerer) || !answerer.client)
		return "gone"
	var/datum/admin_verb/debug_apply_material_treatment/helper = owner
	var/obj/item/stack/material/processed_alloy/held = answerer.get_active_hand()
	if(!istype(held) && !length(helper.nearby_choices(answerer)))
		return "nearby"
	var/obj/item/stack/material/processed_alloy/selected_stock = value
	if(!isnull(value) && !istype(held) && QDELETED(selected_stock))
		return "stock"
	if(!isnull(value) && !isnull(selected_treatment))
		var/obj/item/stack/material/processed_alloy/stock = helper.current_stock(answerer, value, TRUE)
		if(QDELETED(stock) || !answerer.Adjacent(stock))
			return "stock"

/datum/prompt/choice/material_debug_treatment
	rights = R_DEBUG
	timeout = 0
	recheck_on_open = TRUE
	title = "Material Treatment"
	question = "Choose a treatment to apply at full test strength."
	var/nearby_answered = FALSE

/datum/prompt/choice/material_debug_treatment/recheck_extra()
	if(QDELETED(answerer) || !answerer.client)
		return "gone"
	var/datum/admin_verb/debug_apply_material_treatment/helper = owner
	var/obj/item/stack/material/processed_alloy/held = answerer.get_active_hand()
	if(!istype(held) && !length(helper.nearby_choices(answerer)))
		return "nearby"
	if(!isnull(value) && (istype(held) || nearby_answered))
		var/obj/item/stack/material/processed_alloy/stock = helper.current_stock(answerer, subject, nearby_answered)
		if(!value || QDELETED(stock) || !answerer.Adjacent(stock))
			return "stock"

/datum/admin_verb/debug_apply_material_treatment/proc/stock_answered(datum/act/request/context)
	var/datum/prompt/choice/material_debug_stock/request = context.request
	if(!context.answer)
		if(!isnull(request.value) && request.last_error == "nearby")
			to_chat(request.answerer, span_warning("Hold alloy sheets in your active hand or stand near a stack."))
		return
	if(isnull(request.selected_treatment))
		open_treatment(request.answerer, request.value, TRUE)
	else
		var/obj/item/stack/material/processed_alloy/stock = current_stock(request.answerer, request.value, TRUE)
		apply_treatment(request.answerer, stock, request.selected_treatment)

/datum/admin_verb/debug_apply_material_treatment/proc/treatment_answered(datum/act/request/context)
	var/datum/prompt/choice/material_debug_treatment/request = context.request
	if(!context.answer)
		if(!isnull(request.value) && request.last_error == "nearby")
			to_chat(request.answerer, span_warning("Hold alloy sheets in your active hand or stand near a stack."))
		return
	var/obj/item/stack/material/processed_alloy/held = request.answerer.get_active_hand()
	if(!istype(held) && !request.nearby_answered)
		open_stock(request.answerer, nearby_choices(request.answerer), request.value)
	else
		var/obj/item/stack/material/processed_alloy/stock = current_stock(request.answerer, request.subject, request.nearby_answered)
		apply_treatment(request.answerer, stock, request.value)

/datum/admin_verb/debug_apply_material_treatment/proc/apply_treatment(mob/operator, obj/item/stack/material/processed_alloy/stock, selection)
	var/datum/material_batch/batch = stock.physical_batch()?.copy_batch()
	if(!batch)
		return
	var/treatment = GLOB.material_debug_treatments[selection]
	if(findtext(treatment, "lattice") || (treatment in list(MATERIAL_FIELD_RADIATION_HARDENED, MATERIAL_FIELD_ENERGY_STORAGE)))
		batch.add_field_treatment(treatment, 100)
	else
		batch.add_surface_layer(treatment, 100, "debug treatment", 0)
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(stock, batch, operator.drop_location())
	replaced_by(batch, replacement)
	if(replacement)
		operator.put_in_hands(replacement)
		to_chat(operator, span_notice("Applied [lowertext(selection)] to [replacement]."))

/// the output_stock this refers to (a relation view: null once it is deleted).
/obj/machinery/material_furnace/proc/output_stock() as /obj/item/stack/material/processed_alloy
	return output_stock

/// the stock this refers to (a relation view: null once it is deleted).
/obj/structure/material_anvil/proc/stock() as /obj/item/stack/material/processed_alloy
	return stock
