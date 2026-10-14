/// Sale profiles (was /datum/element/sellable). Object state, not an OM behaviour:
/// an object's `sellable_type` names a shared profile singleton (get_sellable_profile())
/// and the cargo shuttle / retail scanner ask the object directly through
/// export_sale() and scan_profit(). Subtypes override the valuation procs.
/datum/sellable
	var/sale_info = "This can be sold on the cargo shuttle if packed in a crate."
	var/needs_crate = TRUE

/// The shared profile singleton for sellable type `path`.
/proc/get_sellable_profile(path)
	var/static/list/profiles = list()
	. = profiles[path]
	if(!.)
		. = new path
		profiles[path] = .

/obj
	/// The /datum/sellable profile this object sells under, or null.
	var/sellable_type

/// Makes this object sellable under profile `path`. The first profile wins.
/obj/proc/make_sellable(path = /datum/sellable)
	if(sellable_type)
		return
	sellable_type = path

/// Offered to the cargo shuttle: TRUE if sold (the crate record is filled in).
/atom/proc/export_sale(datum/exported_crate/EC, in_crate)
	return FALSE

/obj/export_sale(datum/exported_crate/EC, in_crate)
	if(!sellable_type)
		return FALSE
	var/datum/sellable/profile = get_sellable_profile(sellable_type)
	return profile.sell(src, EC, in_crate)

/// The sale value a retail scanner reads, or null when not sellable.
/obj/proc/scan_profit()
	if(!sellable_type)
		return null
	var/datum/sellable/profile = get_sellable_profile(sellable_type)
	return profile.calculate_sell_value(src)

/obj/examine(mob/user, infix = "", suffix = "")
	. = ..()
	if(sellable_type)
		var/datum/sellable/profile = get_sellable_profile(sellable_type)
		if(profile.sale_info)
			. += span_notice(profile.sale_info)

// Override this for sub profiles that need to do complex calculations when sold
/datum/sellable/proc/sell_error(obj/source)
	return null // returns a string explaining why the item couldn't be sold. Otherwise null to allow it to be sold.

/datum/sellable/proc/calculate_sell_value(obj/source)
	return 1

/datum/sellable/proc/calculate_sell_quantity(obj/source)
	return 1
// End overrides

/datum/sellable/proc/sell(obj/source, datum/exported_crate/EC, in_crate)

	if(needs_crate && !in_crate)
		EC.contents = list("error" = "Error: Product was improperly packaged. Payment rendered null under terms of agreement.")
		return FALSE

	var/sell_error = sell_error(source)
	if(sell_error)
		EC.contents = list("error" = sell_error)
		return FALSE

	// The export's rows list (a plain list var on the export datum, not atom contents).
	var/list/rows = EC.contents
	rows[++rows.len] = list(
		"object" = "\proper[source.name]",
		"value" = calculate_sell_value(source),
		"quantity" = calculate_sell_quantity(source)
	)
	var/list/export_row = rows[rows.len]
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
		"physical_item_id" = REF(source),
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
			stock.ensure_feedstock_lot()
			contract_context["material_fingerprint"] = batch.fingerprint()
			contract_context["material_lot_id"] = stock.feedstock_lot_id
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

//////////////////////////////////////////////////////////////////////////////////////////////////////
// Subtypes
//////////////////////////////////////////////////////////////////////////////////////////////////////

// Manifest papers
/datum/sellable/manifest/calculate_sell_value(obj/source)
	var/obj/item/paper/manifest/slip = source
	if(!slip.is_copy && slip.stamped && slip.stamped.len) //yes, the clown stamp will work. clown is the highest authority on the station, it makes sense
		return supply_points_per_slip()
	return 0


// Material stacks
/datum/sellable/material_stack/calculate_sell_value(obj/source)
	var/obj/item/stack/P = source
	var/datum/material/mat = P.get_material()
	if(!mat || !mat.supply_conversion_value)
		return 0
	return P.get_amount() * mat.supply_conversion_value

/datum/sellable/material_stack/calculate_sell_quantity(obj/source)
	var/obj/item/stack/P = source
	return P.get_amount()


// Money
/datum/sellable/spacecash/calculate_sell_value(obj/source)
	var/obj/item/spacecash/cashmoney = source
	return cashmoney.worth * supply_points_per_money()

/datum/sellable/spacecash/calculate_sell_quantity(obj/source)
	var/obj/item/spacecash/cashmoney = source
	return cashmoney.worth

/datum/sellable/manufactured/calculate_sell_value(obj/source)
	return max(1, source.economic_export_value)


// Research samples
/datum/sellable/research_sample/calculate_sell_value(obj/source)
	var/obj/item/research_sample/sample = source
	return sample.supply_value


// Research containers
/datum/sellable/sample_container/calculate_sell_value(obj/source)
	var/obj/item/storage/sample_container/sample_can = source
	var/sample_sum = 0
	var/obj/item/research_sample/stored_sample
	if(LAZYLEN(sample_can.contents))
		for(stored_sample in contents_of(sample_can))
			sample_sum += stored_sample.supply_value
	return sample_sum

/datum/sellable/sample_container/calculate_sell_quantity(obj/source)
	var/obj/item/storage/sample_container/sample_can = source
	return "[sample_can.contents.len] sample(s) "


// Vaccine samples
/datum/sellable/vaccine
	sale_info = "This can be sold on the cargo shuttle if packed in a freezer crate."

/datum/sellable/vaccine/sell_error(obj/source)
	if(!istype(source.loc, /obj/structure/closet/crate/freezer))
		return "Error: Product was improperly packaged. Vaccines must be sold in a freezer crate to preserve for transport. Payment rendered null under terms of agreement."
	var/obj/item/reagent_containers/glass/beaker/vial/vaccine/sale_bottle = source
	if(sale_bottle.reagents.reagent_list.len != 1 || sale_bottle.reagents.get_reagent_amount(REAGENT_ID_VACCINE) < sale_bottle.volume)
		return "Error: Tainted product in vaccine batch. Was opened, contaminated, or wasn't filled to full. Payment rendered null under terms of agreement."
	return null

/datum/sellable/vaccine/calculate_sell_value(obj/source)
	return 5


// Refinery chemical tanks
/datum/sellable/trolley_tank
	sale_info = "This can be sold on the cargo shuttle if filled with a single reagent."
	needs_crate = FALSE

/datum/sellable/trolley_tank/sell_error(obj/source)
	var/obj/vehicle/train/trolley_tank/tank = source
	if(!tank.reagents || tank.reagents.reagent_list.len == 0)
		return "Error: Product was not filled with any reagents to sell. Payment rendered null under terms of agreement."
	var/min_tank = (CARGOTANKER_VOLUME - 100)
	if(tank.reagents.total_volume < min_tank)
		return "Error: Product was improperly packaged. Send full tanks only (minimum [min_tank] units). Payment rendered null under terms of agreement."
	if(tank.reagents.reagent_list.len > 1)
		return "Error: Product was improperly refined. Send purified mixtures only (too many reagents in tank). Payment rendered null under terms of agreement."
	return null

/datum/sellable/trolley_tank/calculate_sell_value(obj/source)
	var/obj/vehicle/train/trolley_tank/tank = source
	if(!length(tank.reagents.reagent_list))
		return 0

	// Update export values
	var/datum/reagent/R = tank.reagents.reagent_list[1]
	var/reagent_value = FLOOR(R.volume * R.supply_conversion_value, 1)

	return reagent_value

/datum/sellable/trolley_tank/calculate_sell_quantity(obj/source)
	var/obj/vehicle/train/trolley_tank/tank = source
	if(!tank.reagents || tank.reagents.reagent_list.len == 0)
		return "0u "
	var/datum/reagent/R = tank.reagents.reagent_list[1]
	return "[R.name] [tank.reagents.total_volume]u "

/datum/sellable/trolley_tank/sell(obj/source, datum/exported_crate/EC, in_crate)
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

/datum/sellable/salvage //For selling /obj/item/salvage

/datum/sellable/salvage/calculate_sell_value(obj/source)
	var/obj/item/salvage/salvagedStuff = source
	return salvagedStuff.worth

/datum/sellable/organ //For selling /obj/item/organ/internal
/datum/sellable/organ/calculate_sell_value(obj/source)
	var/obj/item/organ/internal/organ_stuff = source
	return organ_stuff.supply_conversion_value

/datum/sellable/organ/sell_error(obj/source)
	if(!istype(source.loc, /obj/structure/closet/crate/freezer))
		return "Error: Product was improperly packaged. Send contents in freezer crate to preserve contents for transport."
	var/obj/item/organ/internal/organ_stuff = source
	if(organ_stuff.health != initial(organ_stuff.health) )
		return "Error: Product was damaged on arrival."
	return null
