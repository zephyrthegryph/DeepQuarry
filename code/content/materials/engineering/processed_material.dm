GLOBAL_LIST_EMPTY(processed_material_dedup)

/// What a plain stack carries beyond its material: the traces in it (hidden until assayed) and whether anyone has read them.
/// A stack is like a beaker of solid: sheets of the same material merge whatever lot they came from, traces average by amount,
/// and the merged stack is unassayed if either half was.
/obj/item/stack/material
	/// Substance id -> amount in sheets, for the whole stack (a processed alloy keeps its traces in its batch's composition).
	var/list/trace_amounts
	/// Whether this stack's traces have been rolled (its source's signature contaminants, rolled once when first needed).
	var/traces_rolled = FALSE
	/// Whether a spectrometer has read this stack's traces. Until then the player sees only the base card.
	var/assayed = FALSE

/// The substances a freshly sourced sheet may carry a little of. L4 replaces this roll with per-round and per-lot pools of the source's signature contaminants.
GLOBAL_LIST_INIT(material_stock_trace_pool, list("carbon", "silicon", "sulfur", "oxygen", "lead"))

/// Rolls this stack's traces once. Most stock carries a little of one substance; a processed alloy's are part of its batch instead.
/obj/item/stack/material/proc/ensure_traces()
	if(traces_rolled)
		return
	traces_rolled = TRUE
	if(istype(material, /datum/material/processed_alloy))
		return
	if(prob(80))
		var/trace_id = pick(GLOB.material_stock_trace_pool)
		var/per_sheet = rand(5, 30) / 1000
		LAZYSET(trace_amounts, trace_id, per_sheet * amount)
	material_log("[REF(src)] ([material?.name]) rolled traces [json_encode(trace_amounts)]")

/// Substance id -> percent of the stack's mass, for a spectrometer to read.
/obj/item/stack/material/proc/trace_shares()
	ensure_traces()
	if(istype(material, /datum/material/processed_alloy))
		var/obj/item/stack/material/processed_alloy/processed = src
		var/datum/material_batch/batch = processed.physical_batch()
		return batch ? material_trace_shares(batch.composition, batch.amount) : null
	return material_trace_shares(trace_amounts, amount)

/// A spectrometer reading: reveals the traces in this stack. Returns the lines it printed.
/obj/item/stack/material/proc/assay(mob/user)
	var/list/shares = trace_shares()
	assayed = TRUE
	var/list/lines = material_trace_lines(shares)
	material_log("[REF(src)] ([material?.name]) assayed by [user ? key_name(user) : "nobody"]: [length(lines) ? jointext(lines, "; ") : "clean"]")
	return lines

/// Scales the traces with the sheets: used, split off or taken into a batch, a share of them goes too.
/obj/item/stack/material/proc/scale_traces(factor)
	for(var/id in trace_amounts)
		trace_amounts[id] *= factor

/// Re-point this stack at another registered material. Ordinary sheet types
/// carry their material in the type path, but runtime materials (processed
/// alloys, dynamic/substance materials) live only on the instance, so split
/// copies and material swaps need an explicit setter.
/obj/item/stack/material/proc/set_stack_material(material_name)
	var/datum/material/new_material = get_material_by_name(material_name)
	if(!new_material)
		return FALSE
	set_default_type(material_name)
	set_material(new_material)
	set_recipes(material.get_recipes())
	set_stacktype(material.stack_type)
	if(apply_colour || pass_color)
		set_color(material.icon_colour)
	if(material.conductive())
		flags &= ~NOCONDUCT
	else
		flags |= NOCONDUCT
	update_strings()
	return TRUE

/obj/item/stack/material/copy_stack_properties(obj/item/stack/newstack)
	..()
	var/obj/item/stack/material/copy = newstack
	if(!istype(copy) || !material)
		return
	if(copy.material?.name != material.name)
		copy.set_stack_material(material.name)
	copy.traces_rolled = traces_rolled
	copy.assayed = assayed

/obj/item/stack/material/examine(mob/user)
	. = ..()
	ensure_traces()
	var/list/card = material.card_lines()
	if(material.stat_notes)
		for(var/line in card)
			. += span_notice(line)
	else
		. += span_notice("[jointext(card, ", ")].")
	if(assayed)
		var/list/lines = material_trace_lines(trace_shares())
		var/assay_text = length(lines) ? "Assay: [jointext(lines, "; ")]. Building ignores traces; melting the sheets into a batch does not." : "Assay: no traces."
		. += span_notice(assay_text)
	else
		. += span_notice("Its traces are unassayed; an analyzer reads them.")

/datum/material/processed_alloy
	stack_type = /obj/item/stack/material/processed_alloy
	var/datum/material_batch/batch_template

CAPABILITIES(/datum/material/processed_alloy)
	owns_one(nameof(batch_template), /datum/material_batch)


/proc/register_processed_material(datum/material_batch/batch)
	if(!istype(batch) || !length(batch.composition))
		return null
	batch.recalculate()
	var/fingerprint = batch.fingerprint()
	var/existing = GLOB.processed_material_dedup[fingerprint]
	if(existing && GLOB.name_to_material[existing])
		return existing
	var/key = "processed_alloy_[copytext(fingerprint, 1, 13)]"
	var/datum/material/processed_alloy/material = new
	material.set_name(key)
	material.set_display_name(batch.display_name())
	material.set_use_name(material.display_name)
	rel_set(material, nameof(material.batch_template), batch.copy_batch())
	// A template is a definition, not a piece of stock: it records the temperature stock is made at and holds no heat of its own.
	material.batch_template.settle_heat(null)
	// The card and the traits are the batch's, with the steps behind each number.
	material.set_strength(batch.strength)
	material.set_toughness(batch.toughness)
	material.set_heat_resistance(batch.heat_resistance)
	material.set_conductivity(batch.conductivity)
	material.set_corrosion_resistance(batch.corrosion_resistance)
	material.set_weight(batch.weight)
	material.traits = LAZYCOPY(batch.traits)
	material.stat_notes = batch.stat_notes?.Copy()
	var/weighted_reflectivity = 0
	var/weighted_opacity = 0
	var/weighted_radiation_resistance = 0
	material.composite_material = list()
	for(var/component in batch.composition)
		var/share = LAZYACCESS(batch.composition, component) / max(batch.amount, 1)
		var/datum/material/component_material = get_material_by_name(component)
		if(!component_material)
			continue
		material.composite_material[component] = SHEET_MATERIAL_AMOUNT * share
		weighted_reflectivity += component_material.reflectivity * share
		weighted_opacity += component_material.opacity * share
		weighted_radiation_resistance += component_material.radiation_resistance * share
	var/quality = 100 - batch.flaws
	material.reflectivity = clamp(weighted_reflectivity + quality / 500, 0, 1)
	material.opacity = clamp(weighted_opacity > 0 ? weighted_opacity : 1, 0, 1)
	material.radiation_resistance = max(0, round(weighted_radiation_resistance + material.weight / 12))
	if(material.brittleness() >= 70)
		material.flags |= MATERIAL_BRITTLE
	var/performance_value = (batch.strength + batch.toughness + batch.conductivity + batch.heat_resistance + batch.corrosion_resistance + quality) / 24
	// Sale value follows useful performance. Inefficient processing remains an
	// expense rather than making an otherwise identical material worth more.
	material.supply_conversion_value = clamp(round(performance_value), 5, 80)
	var/datum/material/dominant
	var/dominant_amount = 0
	for(var/component in batch.composition)
		if(LAZYACCESS(batch.composition, component) > dominant_amount && get_material_by_name(component))
			dominant = get_material_by_name(component)
			dominant_amount = LAZYACCESS(batch.composition, component)
	if(dominant)
		material.set_icon_colour(dominant.icon_colour)
	material.material_facts_changed()
	GLOB.name_to_material[key] = material
	GLOB.processed_material_dedup[fingerprint] = key
	material_log("registered [key] ([material.display_name]): strength [material.strength], toughness [material.toughness], heat [material.heat_resistance], conductivity [material.conductivity], corrosion [material.corrosion_resistance], weight [material.weight], traits [json_encode(material.traits)]")
	return key

/proc/processed_spawn_stack(turf/location, datum/material_batch/batch, amount)
	if(!location || !istype(batch))
		return null
	var/material_key = register_processed_material(batch)
	if(!material_key)
		return null
	var/stack_amount = clamp(round(amount || batch.amount), 1, MATERIAL_SCIENCE_MAX_BATCH)
	// Material stacks require a physical location during atom initialization.
	// Stack merging is an explicit later interaction, so constructing directly
	// on the output turf preserves both initialization and the returned ref.
	var/obj/item/stack/material/processed_alloy/stock = new /obj/item/stack/material/processed_alloy(location, stack_amount, material_key)
	own_clear(stock, nameof(stock.batch_state), OWN_DELETE)
	rel_set(stock, nameof(stock.batch_state), batch.copy_for_amount(stack_amount))
	stock.traces_rolled = TRUE
	stock.update_thermal_processing()
	return stock

/obj/item/stack/material/processed_alloy
	name = "alloy sheets"
	desc = "Sheets of a custom alloy, ready for further treatment or fabrication."
	// Temporary recolored metal-sheet sprite until dedicated alloy-stock art exists.
	icon = 'icons/obj/stacks_ch.dmi'
	icon_state = "sheet-metal"
	default_type = MAT_STEEL
	no_variants = TRUE
	pass_color = TRUE
	strict_color_stacking = TRUE
	exotic_no_autolathe_reprint = TRUE
	var/datum/material_batch/batch_state
	/// Export value of one sheet; the stack's total is always this times the
	/// current amount, so splitting/merging/using never creates or destroys value.
	var/export_value_per_sheet = 0

CAPABILITIES(/obj/item/stack/material/processed_alloy)
	setup(PROC_REF(material_processed_alloy_setup))
	owns_one(nameof(batch_state), /datum/material_batch)
	every(2 SECONDS, then(PROC_REF(processed_alloy_step)), when = nameof(hot))
	op("processed_alloy_item", item(/obj/item), then(PROC_REF(processed_alloy_item)))
	param(nameof(default_type), pos = 2)

/obj/item/stack/material/processed_alloy/proc/material_processed_alloy_setup()
	if(istype(material, /datum/material/processed_alloy))
		set_color(material.icon_colour)
		export_value_per_sheet = max(material.supply_conversion_value, 0)
		set_economic_provenance(DEPARTMENT_RESEARCH, export_value_per_sheet * amount)
		var/datum/material/processed_alloy/processed = material
		rel_set(src, nameof(batch_state), processed.batch_template.copy_for_amount(amount))


/// Hot stock's conductance to the air, per J/K of its heat capacity, W/K: the old 8 % of the gap per 2 s step (-ln(0.92) / 2 s).
#define PROCESSED_STOCK_COOLING_RATE 0.0417

/// Hot stock glowing and cooling towards ambient (update_thermal_processing(), processed_alloy_step()).
/obj/item/stack/material/processed_alloy/var/hot = FALSE

/obj/item/stack/material/processed_alloy/proc/physical_batch() as /datum/material_batch
	if(batch_state)
		return batch_state
	var/datum/material/processed_alloy/processed = material
	rel_set(src, nameof(batch_state), processed?.batch_template?.copy_for_amount(amount))
	return batch_state

/obj/item/stack/material/processed_alloy/proc/update_thermal_processing()
	var/datum/material_batch/batch = physical_batch()
	if(batch?.temperature() > T20C + 40)
		set_glow(src, GLOW(2, 1, "#ff7b22"))
		set_hot(TRUE)
	else
		set_glow(src, GLOW(0, null, null))
		set_hot(FALSE)

/// Hot stock cools through a heat link to its turf's air (PROCESSED_STOCK_COOLING_RATE of its capacity, W/K: the old 8 % of the gap per
/// 2 s), and gives the rest to the air and lets its heat store go once within 5 K of it.
/obj/item/stack/material/processed_alloy/proc/processed_alloy_step(datum/act/timer/A)
	var/datum/material_batch/batch = physical_batch()
	if(!batch)
		set_hot(FALSE)
		return
	var/turf/open/turf = get_turf(src)
	var/datum/gas_mixture/air = istype(turf) ? turf.turf_air() : null
	var/ambient_temperature = air ? air.return_temperature() : T20C
	// Solution-treated stock that has cooled past the quench window without being quenched anneals: softer, with fewer flaws.
	if(batch.solution_treated && batch.temperature() < batch.melting_temperature() * 0.62)
		var/datum/material_batch/annealed = batch.copy_batch()
		if(annealed.apply_process(MATERIAL_PROCESS_ANNEAL))
			replace_processed_stack(src, annealed, get_turf(src))
		spent(annealed)
		return
	if(abs(batch.temperature() - ambient_temperature) < 5)
		batch.settle_heat(air ? turf : null)
		set_glow(src, GLOW(0, null, null))
		set_hot(FALSE)
		return
	if(air)
		batch.cool_into(turf, batch.thermal_capacity() * PROCESSED_STOCK_COOLING_RATE)

/obj/item/stack/material/processed_alloy/split(tamount)
	var/old_amount = get_amount()
	var/datum/material_batch/original = physical_batch()?.copy_batch()
	var/obj/item/stack/material/processed_alloy/new_stack = ..()
	if(!new_stack || !original)
		spent(original)
		return new_stack
	new_stack.set_processed_material(material.name)
	new_stack.assayed = assayed
	own_clear(new_stack, nameof(new_stack.batch_state), OWN_DELETE)
	rel_set(new_stack, nameof(new_stack.batch_state), original.copy_for_amount(new_stack.get_amount()))
	rel_clear(src, nameof(batch_state))
	rel_set(src, nameof(batch_state), original.copy_for_amount(max(old_amount - new_stack.get_amount(), 0)))
	spent(original)
	return new_stack

/// Alloy stock merges when it is the same kind: the same bulk materials in the same proportions, the same temper and the same treatments.
/// Its traces average by amount and the merged stock is unassayed if either half was.
/obj/item/stack/material/processed_alloy/can_merge_with(obj/item/stack/material/other)
	var/obj/item/stack/material/processed_alloy/processed_other = other
	if(!istype(processed_other) || !istype(material, /datum/material/processed_alloy) || !istype(processed_other.material, /datum/material/processed_alloy))
		return FALSE
	if(material.name == processed_other.material.name)
		return TRUE
	var/datum/material_batch/mine = physical_batch()
	var/datum/material_batch/theirs = processed_other.physical_batch()
	return mine && theirs && mine.identity() == theirs.identity()

/obj/item/stack/material/processed_alloy/transfer_to(obj/item/stack/target, tamount = null, type_verified)
	var/obj/item/stack/material/processed_alloy/processed_target = target
	if(!istype(processed_target) || !can_merge_with(processed_target))
		return 0
	var/source_before = get_amount()
	var/target_before = processed_target.get_amount()
	var/datum/material_batch/source_batch = physical_batch()?.copy_batch()
	var/datum/material_batch/target_batch = processed_target.physical_batch()?.copy_batch()
	var/both_assayed = assayed && processed_target.assayed
	var/transferred = ..(target, tamount, type_verified)
	if(!transferred)
		consumed(source_batch, src)
		consumed(target_batch, src)
		return 0
	var/datum/material_batch/new_target = target_batch.copy_for_amount(target_before)
	var/datum/material_batch/source_portion = source_batch.copy_for_amount(transferred)
	new_target.absorb(source_portion)
	// The merged stock's traces are the amount-weighted mix, so it is a different registered material when they differ.
	var/new_key = register_processed_material(new_target)
	own_clear(processed_target, nameof(processed_target.batch_state), OWN_DELETE)
	rel_set(processed_target, nameof(processed_target.batch_state), new_target)
	if(new_key && processed_target.material?.name != new_key)
		processed_target.set_processed_material(new_key)
	processed_target.assayed = both_assayed
	processed_target.update_thermal_processing()
	material_log("[REF(src)] merged [transferred] sheets into [REF(processed_target)]: now [new_target.amount] sheets, assayed [both_assayed ? "yes" : "no"]")
	if(!QDELETED(src))
		var/datum/material_batch/new_source = source_batch.copy_for_amount(source_before - transferred)
		rel_clear(src, nameof(batch_state))
		rel_set(src, nameof(batch_state), new_source)
		update_thermal_processing()
	consumed(source_portion, src)
	consumed(source_batch, src)
	consumed(target_batch, src)
	return transferred

/// Every amount mutation on a stack (use/add/set_amount, hence split/merge/
/// transfer) ends in set_amount(), so this is the one seam that keeps the
/// export value in step with the sheets actually present: a split can no
/// longer leave both halves carrying the whole stack's value.
/obj/item/stack/material/processed_alloy/set_amount(new_amount, no_limits = FALSE)
	. = ..()
	if(!QDELETED(src))
		refresh_export_value()

/obj/item/stack/material/processed_alloy/proc/refresh_export_value()
	if(!export_value_per_sheet)
		return
	STATE_SET(src, economy, economic_export_value, max(1, round(export_value_per_sheet * get_amount())))

/obj/item/stack/material/processed_alloy/proc/set_processed_material(material_name)
	var/datum/material/new_material = get_material_by_name(material_name)
	if(!istype(new_material, /datum/material/processed_alloy))
		return FALSE
	set_default_type(material_name)
	set_material(new_material)
	set_recipes(material.get_recipes())
	set_stacktype(material.stack_type)
	set_color(material.icon_colour)
	if(material.conductive())
		flags &= ~NOCONDUCT
	else
		flags |= NOCONDUCT
	update_strings()
	export_value_per_sheet = max(material.supply_conversion_value, 0)
	set_economic_provenance(DEPARTMENT_RESEARCH, export_value_per_sheet * amount)
	return TRUE

/obj/item/stack/material/processed_alloy/examine(mob/user)
	. = ..()
	if(!istype(material, /datum/material/processed_alloy))
		return
	var/datum/material_batch/batch = physical_batch()
	if(batch.temperature() > T20C + 40)
		. += span_warning("The alloy is still dangerously hot.")
	if(length(batch.surface_layers))
		. += span_notice("Surface treatment: [jointext(batch.surface_layers, ", ")].")
	if(length(batch.field_treatments))
		. += span_notice("Field treatment: [jointext(batch.field_treatments, ", ")].")
	var/temper_text = "Temper [round(batch.temper)] (0 soft, 100 hard); flaws [round(batch.flaws)]. [batch.solution_treated ? "Solution-treated: quench it, or let it cool and it anneals." : ""]"
	. += span_notice(temper_text)
