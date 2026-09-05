/datum/element/sellable
	var/sale_info = "This can be sold on the cargo shuttle if packed in a crate."
	var/needs_crate = TRUE

/datum/element/sellable/Attach(datum/target)
	. = ..()
	if(!isobj(target))
		return ELEMENT_INCOMPATIBLE
	var/obj/sellable_object = target
	if(sellable_object.economic_sellable_attached)
		return ELEMENT_INCOMPATIBLE
	sellable_object.economic_sellable_attached = TRUE
	RegisterSignal(target, COMSIG_ITEM_EXPORTED, PROC_REF(sell))
	RegisterSignal(target, COMSIG_ITEM_SCAN_PROFIT, PROC_REF(calculate_sell_value))
	RegisterSignal(target, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	return

/datum/element/sellable/Detach(datum/source)
	var/obj/sellable_object = source
	if(istype(sellable_object))
		sellable_object.economic_sellable_attached = FALSE
	UnregisterSignal(source, COMSIG_ITEM_EXPORTED)
	UnregisterSignal(source, COMSIG_ITEM_SCAN_PROFIT)
	UnregisterSignal(source, COMSIG_ATOM_EXAMINE)
	return ..()

// Override this for sub elements that need to do complex calculations when sold
/datum/element/sellable/proc/sell_error(obj/source)
	return null // returns a string explaining why the item couldn't be sold. Otherwise null to allow it to be sold.

/datum/element/sellable/proc/calculate_sell_value(obj/source)
	SIGNAL_HANDLER
	return 1

/datum/element/sellable/proc/calculate_sell_quantity(obj/source)
	return 1
// End overrides

/datum/element/sellable/proc/sell(obj/source, datum/exported_crate/EC, in_crate)
	SIGNAL_HANDLER

	if(needs_crate && !in_crate)
		EC.contents = list("error" = "Error: Product was improperly packaged. Payment rendered null under terms of agreement.")
		return FALSE

	var/sell_error = sell_error(source)
	if(sell_error)
		EC.contents = list("error" = sell_error)
		return FALSE

	EC.contents[++EC.contents.len] = list(
		"object" = "\proper[source.name]",
		"value" = calculate_sell_value(source),
		"quantity" = calculate_sell_quantity(source)
	)
	var/list/export_row = EC.contents[EC.contents.len]
	SSsupply.apply_market_demand(source, EC, export_row)
	EC.value += export_row["value"]
	if(EC.sales_ledger_valid && source.economic_department == EC.sales_department)
		EC.sales_eligible_value += export_row["value"]
	else if(source.economic_department)
		LAZYINITLIST(EC.revenue_by_department)
		EC.revenue_by_department[source.economic_department] += export_row["value"]
		if(source.economic_producer_account)
			LAZYINITLIST(EC.revenue_by_producer)
			var/producer_key = "[source.economic_producer_account]"
			EC.revenue_by_producer[producer_key] += export_row["value"]
	var/list/contract_context = list(
		"actor_account" = source.economic_producer_account,
		"department" = source.economic_department,
		"origin_department" = source.economic_department,
		// All accepted shuttle freight is handled by Cargo, including salvage,
		// raw materials, and another department's manufactured goods.
		"handling_department" = DEPARTMENT_CARGO,
		"freight_ledger_id" = EC.sales_ledger_id,
		"freight_destination" = EC.sales_destination,
		"routed_department" = EC.sales_department,
		"item_type" = source.type,
		"item_name" = source.name,
		"quantity" = export_row["quantity"],
		"in_crate" = in_crate,
		"fact_id" = "export:[REF(source)]",
		"fact_revision" = 1,
		"fact_active" = TRUE,
		"metrics" = list("value" = SSsupply.export_revenue(export_row["value"])),
		"detail" = "Accepted export of [source.name]",
	)
	if(istype(source, /obj/item/stack/material/processed_alloy))
		var/obj/item/stack/material/processed_alloy/stock = source
		var/datum/material_batch/batch = stock.physical_batch()
		if(batch)
			contract_context["material_fingerprint"] = batch.fingerprint()
			contract_context["material_amount"] = stock.get_amount()
			contract_context["purity"] = batch.purity
			contract_context["hardness"] = batch.hardness
			contract_context["toughness"] = batch.toughness
			contract_context["conductivity"] = batch.conductivity
			contract_context["heat_resistance"] = batch.heat_resistance
			contract_context["corrosion_resistance"] = batch.corrosion_resistance
			contract_context["defect_fraction"] = batch.structure[MATERIAL_STRUCTURE_DEFECT]
			contract_context["oxidation"] = batch.oxidation
	emit_contract_event(CONTRACT_EVENT_ITEM_EXPORTED, contract_context, "item-exported:[REF(source)]", source)
	return TRUE

/datum/element/sellable/proc/on_examine(datum/source, mob/user, list/examine_texts)
	SIGNAL_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	if(sale_info)
		examine_texts += span_notice(sale_info)

//////////////////////////////////////////////////////////////////////////////////////////////////////
// Subtypes
//////////////////////////////////////////////////////////////////////////////////////////////////////

// Manifest papers
/datum/element/sellable/manifest/calculate_sell_value(obj/source)
	var/obj/item/paper/manifest/slip = source
	if(!slip.is_copy && slip.stamped && slip.stamped.len) //yes, the clown stamp will work. clown is the highest authority on the station, it makes sense
		return SSsupply.points_per_slip
	return 0


// Material stacks
/datum/element/sellable/material_stack/calculate_sell_value(obj/source)
	var/obj/item/stack/P = source
	var/datum/material/mat = P.get_material()
	if(!mat || !mat.supply_conversion_value)
		return 0
	return P.get_amount() * mat.supply_conversion_value

/datum/element/sellable/material_stack/calculate_sell_quantity(obj/source)
	var/obj/item/stack/P = source
	return P.get_amount()


// Money
/datum/element/sellable/spacecash/calculate_sell_value(obj/source)
	var/obj/item/spacecash/cashmoney = source
	return cashmoney.worth * SSsupply.points_per_money

/datum/element/sellable/spacecash/calculate_sell_quantity(obj/source)
	var/obj/item/spacecash/cashmoney = source
	return cashmoney.worth

/datum/element/sellable/manufactured/calculate_sell_value(obj/source)
	return max(1, source.economic_export_value)


// Research samples
/datum/element/sellable/research_sample/calculate_sell_value(obj/source)
	var/obj/item/research_sample/sample = source
	return sample.supply_value


// Research containers
/datum/element/sellable/sample_container/calculate_sell_value(obj/source)
	var/obj/item/storage/sample_container/sample_can = source
	var/sample_sum = 0
	var/obj/item/research_sample/stored_sample
	if(LAZYLEN(sample_can.contents))
		for(stored_sample in sample_can.contents)
			sample_sum += stored_sample.supply_value
	return sample_sum

/datum/element/sellable/sample_container/calculate_sell_quantity(obj/source)
	var/obj/item/storage/sample_container/sample_can = source
	return "[sample_can.contents.len] sample(s) "


// Vaccine samples
/datum/element/sellable/vaccine
	sale_info = "This can be sold on the cargo shuttle if packed in a freezer crate."

/datum/element/sellable/vaccine/sell_error(obj/source)
	if(!istype(source.loc, /obj/structure/closet/crate/freezer))
		return "Error: Product was improperly packaged. Vaccines must be sold in a freezer crate to preserve for transport. Payment rendered null under terms of agreement."
	var/obj/item/reagent_containers/glass/beaker/vial/vaccine/sale_bottle = source
	if(sale_bottle.reagents.reagent_list.len != 1 || sale_bottle.reagents.get_reagent_amount(REAGENT_ID_VACCINE) < sale_bottle.volume)
		return "Error: Tainted product in vaccine batch. Was opened, contaminated, or wasn't filled to full. Payment rendered null under terms of agreement."
	return null

/datum/element/sellable/vaccine/calculate_sell_value(obj/source)
	return 5


// Refinery chemical tanks
/datum/element/sellable/trolley_tank
	sale_info = "This can be sold on the cargo shuttle if filled with a single reagent."
	needs_crate = FALSE

/datum/element/sellable/trolley_tank/sell_error(obj/source)
	var/obj/vehicle/train/trolley_tank/tank = source
	if(!tank.reagents || tank.reagents.reagent_list.len == 0)
		return "Error: Product was not filled with any reagents to sell. Payment rendered null under terms of agreement."
	var/min_tank = (CARGOTANKER_VOLUME - 100)
	if(tank.reagents.total_volume < min_tank)
		return "Error: Product was improperly packaged. Send full tanks only (minimum [min_tank] units). Payment rendered null under terms of agreement."
	if(tank.reagents.reagent_list.len > 1)
		return "Error: Product was improperly refined. Send purified mixtures only (too many reagents in tank). Payment rendered null under terms of agreement."
	return null

/datum/element/sellable/trolley_tank/calculate_sell_value(obj/source)
	var/obj/vehicle/train/trolley_tank/tank = source
	if(!length(tank.reagents.reagent_list))
		return 0

	// Update export values
	var/datum/reagent/R = tank.reagents.reagent_list[1]
	var/reagent_value = FLOOR(R.volume * R.supply_conversion_value, 1)

	return reagent_value

/datum/element/sellable/trolley_tank/calculate_sell_quantity(obj/source)
	var/obj/vehicle/train/trolley_tank/tank = source
	if(!tank.reagents || tank.reagents.reagent_list.len == 0)
		return "0u "
	var/datum/reagent/R = tank.reagents.reagent_list[1]
	return "[R.name] [tank.reagents.total_volume]u "

/datum/element/sellable/trolley_tank/sell(obj/source, datum/exported_crate/EC, in_crate)
	. = ..()
	var/obj/vehicle/train/trolley_tank/tank = source
	if(. && tank.reagents?.reagent_list?.len)
		// Update end round data, has nothing to do with actual cargo sales
		var/datum/reagent/R = tank.reagents.reagent_list[1]
		var/reagent_value = FLOOR(R.volume * R.supply_conversion_value, 1)
		if(R.industrial_use)
			if(isnull(GLOB.refined_chems_sold[R.industrial_use]))
				var/list/data = list()
				data["units"] = FLOOR(R.volume, 1)
				data["value"] = reagent_value
				GLOB.refined_chems_sold[R.industrial_use] = data
			else
				GLOB.refined_chems_sold[R.industrial_use]["units"] += FLOOR(R.volume, 1)
				GLOB.refined_chems_sold[R.industrial_use]["value"] += reagent_value

/datum/element/sellable/salvage //For selling /obj/item/salvage

/datum/element/sellable/salvage/calculate_sell_value(obj/source)
	var/obj/item/salvage/salvagedStuff = source
	return salvagedStuff.worth

/datum/element/sellable/organ //For selling /obj/item/organ/internal
/datum/element/sellable/organ/calculate_sell_value(obj/source)
	var/obj/item/organ/internal/organ_stuff = source
	return organ_stuff.supply_conversion_value

/datum/element/sellable/organ/sell_error(obj/source)
	if(!istype(source.loc, /obj/structure/closet/crate/freezer))
		return "Error: Product was improperly packaged. Send contents in freezer crate to preserve contents for transport."
	var/obj/item/organ/internal/organ_stuff = source
	if(organ_stuff.health != initial(organ_stuff.health) )
		return "Error: Product was damaged on arrival."
	return null
