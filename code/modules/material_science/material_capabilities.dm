/// Emergent, reusable mechanics carried by processed materials into manufactured forms.
/// Capability derivation is deterministic: composition, microstructure, processing, and
/// incorporated catalysts decide what a batch can do. Item components then consume the
/// same capability table through ordinary game signals, irrespective of the item recipe.

/datum/material
	var/list/material_capabilities

/datum/material/proc/material_capability(capability_id)
	return material_capabilities?[capability_id] || 0

/datum/material/proc/has_material_capability(capability_id)
	return material_capability(capability_id) > 0

/datum/material/proc/derive_material_capabilities()
	return

/datum/material/processed_alloy/derive_material_capabilities()
	var/datum/material_batch/batch = batch_template
	if(!batch)
		return
	var/list/result = list()
	var/list/composition = batch.composition
	var/list/additives = batch.impurities
	var/has_crystal = composition[MAT_QUARTZ] || composition[MAT_DIAMOND] || composition[MAT_GLASS]
	var/has_biological = composition[MAT_BIOMASS] || composition[MAT_FLESH] || composition[MAT_CHITIN] || composition[MAT_ALIENCHITIN]
	var/has_ferrous = composition[MAT_IRON] || composition[MAT_STEEL] || composition[MAT_DURASTEEL]
	var/has_precious_catalyst = composition[MAT_PLATINUM] || composition[MAT_GOLD] || composition[MAT_SILVER]
	var/has_radioisotope = composition[MAT_URANIUM] || composition[MAT_TRITIUM]

	if(additives["thermal phase catalyst"] && batch.conductivity >= 45)
		result[MATERIAL_CAP_THERMOELECTRIC] = clamp(round((batch.conductivity + batch.heat_resistance) / 2), 25, 100)
	if(has_crystal && batch.conductivity >= 30 && batch.homogeneity >= 70)
		result[MATERIAL_CAP_PIEZOELECTRIC] = clamp(round((batch.conductivity + batch.homogeneity - batch.porosity) / 2), 20, 100)
	if(additives["conductive dopant"] && batch.conductivity >= 40 && batch.homogeneity >= 60)
		result[MATERIAL_CAP_ELECTROGENIC] = clamp(round((batch.conductivity + batch.homogeneity) / 2), 25, 100)
	if((composition[MAT_MORPHIUM] || (composition[MAT_TITANIUM] && batch.structure[MATERIAL_STRUCTURE_HARDENED] >= 20)) && batch.toughness >= 55)
		result[MATERIAL_CAP_SHAPE_MEMORY] = clamp(round((batch.toughness + batch.homogeneity - batch.internal_stress) / 2), 20, 100)
	if((composition[MAT_METALHYDROGEN] || additives["cryogenic stabilizer"]) && batch.conductivity >= 75 && batch.purity >= 90)
		result[MATERIAL_CAP_SUPERCONDUCTING] = clamp(round((batch.conductivity + batch.purity) / 2), 40, 100)
	if(has_precious_catalyst && batch.purity >= 80 && batch.surface_protection >= 5)
		result[MATERIAL_CAP_CATALYTIC] = clamp(round((batch.purity + batch.corrosion_resistance) / 2), 20, 100)
	if(composition[MAT_SILVER] && batch.corrosion_resistance >= 50)
		result[MATERIAL_CAP_ANTIMICROBIAL] = clamp(round((batch.corrosion_resistance + batch.purity) / 2), 25, 100)
	if(has_biological && (composition[MAT_IRON] || additives["precipitation catalyst"]))
		result[MATERIAL_CAP_HEMOSTATIC] = clamp(round((batch.homogeneity + batch.purity) / 2), 20, 100)
	if(has_biological && (composition[MAT_MORPHIUM] || batch.structure[MATERIAL_STRUCTURE_AMORPHOUS] >= 20))
		result[MATERIAL_CAP_BIOMIMETIC] = clamp(round((batch.toughness + batch.homogeneity) / 2), 20, 100)
	if(has_radioisotope && batch.conductivity >= 35)
		result[MATERIAL_CAP_RADIOVOLTAIC] = clamp(round((batch.conductivity + radioactivity) / 2), 20, 100)
	if(has_radioisotope && has_crystal && batch.homogeneity >= 65)
		result[MATERIAL_CAP_SCINTILLATING] = clamp(round((batch.homogeneity + reflectivity * 100) / 2), 20, 100)
	if(has_ferrous && batch.conductivity >= 45 && batch.structure[MATERIAL_STRUCTURE_HARDENED] >= 15)
		result[MATERIAL_CAP_MAGNETOSTRICTIVE] = clamp(round((batch.hardness + batch.conductivity) / 2), 20, 100)
	if((batch.infused_substance?.family == SUBFAM_FIELD) || (composition[MAT_PLASTEEL] && batch.structure[MATERIAL_STRUCTURE_PRECIPITATE] >= 20))
		result[MATERIAL_CAP_REACTIVE_ARMOR] = clamp(round((batch.toughness + batch.hardness) / 2), 25, 100)
	if(additives["thermal phase catalyst"] && batch.heat_resistance >= 60)
		result[MATERIAL_CAP_PHASE_CHANGE] = clamp(round((batch.heat_resistance + batch.toughness) / 2), 25, 100)
	if(batch.porosity >= 18 && (composition[MAT_TITANIUM] || composition[MAT_ALUMINIUM] || composition[MAT_GRAPHITE]))
		result[MATERIAL_CAP_GAS_GETTER] = clamp(round(batch.porosity * 2 + batch.corrosion_resistance / 3), 20, 100)
	if(batch.porosity >= 22 && batch.corrosion_resistance >= 45)
		result[MATERIAL_CAP_POROUS_REAGENT] = clamp(round(batch.porosity * 2 + batch.corrosion_resistance / 3), 20, 100)
	if(has_crystal && batch.homogeneity >= 80 && reflectivity >= 0.25)
		result[MATERIAL_CAP_OPTICAL] = clamp(round(batch.homogeneity * 0.6 + reflectivity * 40), 20, 100)
	if(batch.infused_substance && additives["bluespace homogenizer"])
		result[MATERIAL_CAP_RESONANT] = clamp(round((batch.homogeneity + batch.infused_substance.affinity) / 2), 25, 100)
	material_capabilities = length(result) ? result : null

/proc/material_capability_name(capability_id)
	switch(capability_id)
		if(MATERIAL_CAP_THERMOELECTRIC) return "thermoelectric lattice"
		if(MATERIAL_CAP_PIEZOELECTRIC) return "piezoelectric lattice"
		if(MATERIAL_CAP_ELECTROGENIC) return "electrogenic matrix"
		if(MATERIAL_CAP_SHAPE_MEMORY) return "shape-memory recovery"
		if(MATERIAL_CAP_SUPERCONDUCTING) return "cryogenic superconductivity"
		if(MATERIAL_CAP_CATALYTIC) return "surface catalysis"
		if(MATERIAL_CAP_ANTIMICROBIAL) return "antimicrobial surface"
		if(MATERIAL_CAP_HEMOSTATIC) return "hemostatic interface"
		if(MATERIAL_CAP_BIOMIMETIC) return "biomimetic integration"
		if(MATERIAL_CAP_RADIOVOLTAIC) return "radiovoltaic conversion"
		if(MATERIAL_CAP_SCINTILLATING) return "scintillation"
		if(MATERIAL_CAP_MAGNETOSTRICTIVE) return "magnetostrictive response"
		if(MATERIAL_CAP_REACTIVE_ARMOR) return "reactive armor discharge"
		if(MATERIAL_CAP_PHASE_CHANGE) return "phase-change heat reservoir"
		if(MATERIAL_CAP_GAS_GETTER) return "selective gas sorption"
		if(MATERIAL_CAP_POROUS_REAGENT) return "porous reagent reservoir"
		if(MATERIAL_CAP_OPTICAL) return "optical metamaterial response"
		if(MATERIAL_CAP_RESONANT) return "resonant material signature"
	return capability_id

/datum/material_batch/proc/material_capability_preview()
	var/datum/material/processed_alloy/preview = new
	preview.batch_template = src
	var/weighted_reflectivity = 0
	var/weighted_radioactivity = 0
	for(var/component_id in composition)
		var/datum/material/component_material = get_material_by_name(component_id)
		if(!component_material)
			continue
		var/share = composition[component_id] / max(amount, 1)
		weighted_reflectivity += component_material.reflectivity * share
		weighted_radioactivity += dq_material_radioactivity(component_material) * share
	preview.reflectivity = weighted_reflectivity
	preview.radioactivity = weighted_radioactivity
	preview.derive_material_capabilities()
	var/list/result = list()
	for(var/capability_id in preview.material_capabilities)
		result += list(list("id" = capability_id, "name" = material_capability_name(capability_id), "potency" = preview.material_capabilities[capability_id]))
	preview.batch_template = null
	qdel(preview)
	return result

/datum/material/proc/dq_apply_material_capabilities(obj/item/item)
	if(item && length(material_capabilities))
		item.AddComponent(/datum/component/material_capabilities, src)

/datum/component/material_capabilities
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/material_id
	var/list/capabilities
	var/next_activation = 0
	var/reactive_charges = MATERIAL_CAPABILITY_MAX_CHARGES
	var/stored_phase_energy = 0
	var/stored_gas_moles = 0
	var/stored_gas_type
	var/processing = FALSE
	var/scintillation_timer

/datum/component/material_capabilities/Initialize(datum/material/material)
	. = ..()
	if(!isitem(parent) || !istype(material) || !length(material.material_capabilities))
		return COMPONENT_INCOMPATIBLE
	material_id = material.name
	capabilities = material.material_capabilities.Copy()
	if(capabilities[MATERIAL_CAP_POROUS_REAGENT])
		var/obj/item/item = parent
		item.create_reagents(clamp(round(capabilities[MATERIAL_CAP_POROUS_REAGENT] / 4), 5, 25))
	if(capabilities[MATERIAL_CAP_SHAPE_MEMORY] || capabilities[MATERIAL_CAP_THERMOELECTRIC] || capabilities[MATERIAL_CAP_ELECTROGENIC] || capabilities[MATERIAL_CAP_RADIOVOLTAIC] || capabilities[MATERIAL_CAP_PHASE_CHANGE] || capabilities[MATERIAL_CAP_GAS_GETTER] || capabilities[MATERIAL_CAP_CATALYTIC])
		START_PROCESSING(SSobj, src)
		processing = TRUE

/datum/component/material_capabilities/Destroy(force)
	if(processing)
		STOP_PROCESSING(SSobj, src)
	if(scintillation_timer)
		deltimer(scintillation_timer)
	capabilities = null
	return ..()

/datum/component/material_capabilities/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_ATOM_TAKE_DAMAGE, PROC_REF(on_take_damage))
	RegisterSignal(parent, COMSIG_ATOM_PRE_EMP_ACT, PROC_REF(on_pre_emp))
	RegisterSignal(parent, COMSIG_ATOM_FIRE_ACT, PROC_REF(on_fire))
	RegisterSignal(parent, COMSIG_ATOM_PROPAGATE_RAD_PULSE, PROC_REF(on_radiation))
	RegisterSignal(parent, COMSIG_ATOM_ATTACKBY, PROC_REF(on_attackby))
	RegisterSignal(parent, COMSIG_ITEM_ATTACK_SELF, PROC_REF(on_attack_self))
	RegisterSignal(parent, COMSIG_MATERIAL_SURGERY, PROC_REF(on_surgery))

/datum/component/material_capabilities/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EXAMINE, COMSIG_ATOM_TAKE_DAMAGE, COMSIG_ATOM_PRE_EMP_ACT, COMSIG_ATOM_FIRE_ACT, COMSIG_ATOM_PROPAGATE_RAD_PULSE, COMSIG_ATOM_ATTACKBY, COMSIG_ITEM_ATTACK_SELF, COMSIG_MATERIAL_SURGERY))

/datum/component/material_capabilities/proc/capability(capability_id)
	return capabilities?[capability_id] || 0

/datum/component/material_capabilities/proc/ambient_temperature()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	return air ? air.return_temperature() : T20C

/datum/component/material_capabilities/process(seconds_per_tick)
	var/obj/item/item = parent
	if(QDELETED(item))
		return PROCESS_KILL
	var/temperature = ambient_temperature()
	var/obj/item/cell/cell = istype(item, /obj/item/cell) ? item : item.get_cell()
	var/thermoelectric = capability(MATERIAL_CAP_THERMOELECTRIC)
	if(cell && thermoelectric && abs(temperature - T20C) >= 35)
		cell.give(max(1, round(thermoelectric * abs(temperature - T20C) / 500)))
	var/radiovoltaic = capability(MATERIAL_CAP_RADIOVOLTAIC)
	if(cell && radiovoltaic)
		cell.give(max(1, round(radiovoltaic / 12)))
	var/electrogenic = capability(MATERIAL_CAP_ELECTROGENIC)
	if(cell && electrogenic)
		cell.give(max(1, round(electrogenic / 12)))
	var/shape_memory = capability(MATERIAL_CAP_SHAPE_MEMORY)
	if(shape_memory && temperature >= T0C + 80 && temperature <= T0C + 500 && item.get_integrity() < item.max_integrity)
		item.repair_damage(max(1, round(shape_memory / 20)))
	var/phase_change = capability(MATERIAL_CAP_PHASE_CHANGE)
	if(phase_change && temperature > T0C + 60)
		stored_phase_energy = min(stored_phase_energy + phase_change * seconds_per_tick, phase_change * 100)
		var/turf/hot_turf = get_turf(item)
		var/datum/gas_mixture/hot_air = hot_turf?.return_air()
		if(hot_air)
			hot_air.set_temperature(max(T20C, temperature - phase_change / 80))
	else if(stored_phase_energy > 0 && temperature < T0C + 20)
		stored_phase_energy = max(0, stored_phase_energy - phase_change * seconds_per_tick)
		var/turf/cold_turf = get_turf(item)
		var/datum/gas_mixture/cold_air = cold_turf?.return_air()
		if(cold_air)
			cold_air.set_temperature(min(T20C, temperature + phase_change / 100))
	if(capability(MATERIAL_CAP_GAS_GETTER))
		process_gas_getter()
	if(capability(MATERIAL_CAP_CATALYTIC))
		process_catalytic_surface()

/datum/component/material_capabilities/proc/process_catalytic_surface()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air)
		return
	var/miasma = air.get_moles(/datum/gas/miasma)
	if(miasma <= 0.001)
		return
	var/converted = min(miasma, max(0.001, capability(MATERIAL_CAP_CATALYTIC) / 5000))
	air.adjust_moles(/datum/gas/miasma, -converted)
	air.adjust_moles(/datum/gas/oxygen, converted)

/datum/component/material_capabilities/proc/process_gas_getter()
	if(stored_gas_moles >= capability(MATERIAL_CAP_GAS_GETTER) / 5)
		return
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air)
		return
	var/list/candidates = stored_gas_type ? list(stored_gas_type) : list(/datum/gas/plasma, /datum/gas/miasma, /datum/gas/carbon_dioxide)
	for(var/gas_path in candidates)
		var/available = air.get_moles(gas_path)
		if(available <= 0.01)
			continue
		var/take = min(available, max(0.01, capability(MATERIAL_CAP_GAS_GETTER) / 1000))
		air.adjust_moles(gas_path, -take)
		stored_gas_type = gas_path
		stored_gas_moles += take
		return

/datum/component/material_capabilities/proc/on_examine(datum/source, mob/user, list/examine_text)
	SIGNAL_HANDLER
	for(var/capability_id in capabilities)
		examine_text += span_notice("Material capability: <b>[material_capability_name(capability_id)]</b> ([capabilities[capability_id]]%).")
	if(stored_gas_moles > 0)
		examine_text += span_notice("Its getter lattice contains [round(stored_gas_moles, 0.01)] moles of captured gas.")
	if(stored_phase_energy > 0)
		examine_text += span_notice("Its phase reservoir is [round(stored_phase_energy / max(capability(MATERIAL_CAP_PHASE_CHANGE), 1))]% charged with heat.")

/datum/component/material_capabilities/proc/on_take_damage(datum/source, damage_amount, damage_type, damage_flag, sound_effect, attack_dir, armour_penetration)
	SIGNAL_HANDLER
	if(capability(MATERIAL_CAP_REACTIVE_ARMOR) && reactive_charges > 0 && world.time >= next_activation && damage_amount >= 5)
		reactive_charges--
		next_activation = world.time + MATERIAL_CAPABILITY_COOLDOWN
		new /obj/effect/effect/sparks(get_turf(parent))
		return COMPONENT_NO_TAKE_DAMAGE

/datum/component/material_capabilities/proc/on_pre_emp(datum/source, severity)
	SIGNAL_HANDLER
	if(capability(MATERIAL_CAP_SUPERCONDUCTING) && ambient_temperature() <= T0C)
		return EMP_PROTECT_SELF

/datum/component/material_capabilities/proc/on_fire(datum/source, exposed_temperature, exposed_volume)
	SIGNAL_HANDLER
	var/phase_change = capability(MATERIAL_CAP_PHASE_CHANGE)
	if(phase_change)
		stored_phase_energy = min(stored_phase_energy + exposed_temperature * exposed_volume / 100, phase_change * 100)
	if(stored_gas_moles > 0 && exposed_temperature >= T0C + 100)
		release_stored_gas()

/datum/component/material_capabilities/proc/on_radiation(datum/source, atom/pulse_source)
	SIGNAL_HANDLER
	var/scintillating = capability(MATERIAL_CAP_SCINTILLATING)
	if(scintillating)
		var/obj/item/item = parent
		item.set_light(clamp(scintillating / 20, 1, 5), clamp(scintillating / 35, 0.5, 3), "#88ddff")
		if(scintillation_timer)
			deltimer(scintillation_timer)
		scintillation_timer = addtimer(CALLBACK(src, PROC_REF(end_scintillation)), 5 SECONDS, TIMER_STOPPABLE)

/datum/component/material_capabilities/proc/end_scintillation()
	scintillation_timer = null
	var/obj/item/item = parent
	if(istype(item))
		var/datum/material/material = item.get_material()
		var/base_light = dq_material_luminescence(material)
		if(base_light > 0)
			item.set_light(clamp(base_light / 20, 0.5, 4), clamp(base_light / 30, 0.3, 2), material.icon_colour)
		else
			item.set_light(0)

/datum/component/material_capabilities/proc/on_attackby(datum/source, obj/item/weapon, mob/living/user, list/modifiers)
	SIGNAL_HANDLER
	if(!capability(MATERIAL_CAP_POROUS_REAGENT) || !weapon?.reagents?.total_volume)
		return
	var/obj/item/item = parent
	var/transferred = weapon.reagents.trans_to(item, min(5, weapon.reagents.total_volume))
	if(transferred)
		to_chat(user, span_notice("The porous lattice absorbs [transferred] units from [weapon]."))

/datum/component/material_capabilities/proc/on_form_trigger(condition, turf/where, atom/cause)
	if(condition == SUB_TRIG_IMPACT)
		var/piezoelectric = capability(MATERIAL_CAP_PIEZOELECTRIC)
		var/obj/item/item = parent
		var/obj/item/cell/cell = istype(item, /obj/item/cell) ? item : item.get_cell()
		if(cell && piezoelectric)
			cell.give(max(1, round(piezoelectric / 3)))
		if(capability(MATERIAL_CAP_POROUS_REAGENT) && item.reagents?.total_volume && isliving(cause))
			item.reagents.trans_to(cause, min(2, item.reagents.total_volume))

/datum/component/material_capabilities/proc/on_attack_self(datum/source, mob/living/user)
	SIGNAL_HANDLER
	if(world.time < next_activation)
		return
	next_activation = world.time + MATERIAL_CAPABILITY_COOLDOWN
	if(capability(MATERIAL_CAP_MAGNETOSTRICTIVE))
		for(var/obj/item/other in range(7, user))
			var/datum/material/other_material = other.get_material()
			if(other == parent || other.anchored || other_material?.name != material_id)
				continue
			other.throw_at(user, 7, 2, user)
		user.visible_message(span_notice("[parent] emits a magnetic retrieval pulse."))
	if(capability(MATERIAL_CAP_RESONANT))
		var/list/findings = list()
		for(var/obj/item/other in range(10, user))
			var/datum/material/other_material = other.get_material()
			if(other != parent && other_material?.name == material_id)
				findings += "[other] ([get_dist(user, other)] tiles [dir2text(get_dir(user, other))])"
		to_chat(user, span_notice(length(findings) ? "The resonant response locates [jointext(findings, ", ")]." : "No matching material answers the resonance pulse."))
	if(capability(MATERIAL_CAP_OPTICAL))
		var/obj/item/item = parent
		item.alpha = item.alpha < 255 ? 255 : 110
		to_chat(user, span_notice("The optical lattice [item.alpha < 255 ? "bends light around itself" : "returns to its opaque state"]."))
	if(stored_gas_moles > 0)
		release_stored_gas()

/datum/component/material_capabilities/proc/release_stored_gas()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air || !stored_gas_type || stored_gas_moles <= 0)
		return
	air.adjust_moles(stored_gas_type, stored_gas_moles)
	stored_gas_moles = 0
	stored_gas_type = null

/datum/component/material_capabilities/proc/on_surgery(datum/source, mob/living/carbon/human/target, target_zone, successful)
	SIGNAL_HANDLER
	if(!successful || !istype(target))
		return
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected)
		return
	var/antimicrobial = capability(MATERIAL_CAP_ANTIMICROBIAL)
	if(antimicrobial)
		affected.germ_level = max(0, affected.germ_level - antimicrobial * 2)
		target.germ_level = max(0, target.germ_level - antimicrobial)
	var/hemostatic = capability(MATERIAL_CAP_HEMOSTATIC)
	if(hemostatic)
		if(hemostatic >= 50)
			affected.organ_clamp()
		for(var/datum/wound/internal_bleeding/wound in affected.wounds)
			wound.clamped = TRUE
	var/biomimetic = capability(MATERIAL_CAP_BIOMIMETIC)
	if(biomimetic && affected.brute_dam + affected.burn_dam > 0)
		affected.heal_damage(max(1, round(biomimetic / 20)), 0, 0, 1)

/obj/item/proc/material_capability_activate(capability_id)
	var/datum/component/material_capabilities/component = GetComponent(/datum/component/material_capabilities)
	if(!component || !component.capability(capability_id) || component.reactive_charges <= 0 || world.time < component.next_activation)
		return FALSE
	component.reactive_charges--
	component.next_activation = world.time + MATERIAL_CAPABILITY_COOLDOWN
	new /obj/effect/effect/sparks(get_turf(src))
	return TRUE

/obj/item/proc/material_capability_form_trigger(condition, turf/where, atom/cause)
	var/datum/component/material_capabilities/component = GetComponent(/datum/component/material_capabilities)
	if(component)
		component.on_form_trigger(condition, where, cause)

/obj/item/proc/material_cell_use_cost(amount)
	var/datum/material/material = get_material()
	var/superconducting = material?.material_capability(MATERIAL_CAP_SUPERCONDUCTING)
	if(!superconducting)
		return amount
	var/turf/turf = get_turf(src)
	var/datum/gas_mixture/air = turf?.return_air()
	var/temperature = air ? air.return_temperature() : T20C
	if(temperature <= T0C)
		return amount * clamp(1 - superconducting / 125, 0.15, 0.8)
	if(temperature >= T0C + 80)
		new /obj/effect/effect/sparks(turf)
		return amount * 1.5
	return amount
