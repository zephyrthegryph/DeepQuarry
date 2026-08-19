/// Emergent mechanics carried by processed materials into appropriate manufactured forms.
/// Derivation is deterministic; observation is progressive; runtime effects are event-driven.

GLOBAL_LIST_EMPTY(material_radiovoltaic_items)

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

/proc/material_capability_discovered(capability_id, datum/material_batch/batch)
	if(!batch)
		return FALSE
	switch(capability_id)
		if(MATERIAL_CAP_THERMOELECTRIC, MATERIAL_CAP_ELECTROGENIC, MATERIAL_CAP_SUPERCONDUCTING, MATERIAL_CAP_RADIOVOLTAIC)
			return !isnull(batch.test_results[MATERIAL_TEST_CONDUCTIVITY]) && !isnull(batch.test_results[MATERIAL_TEST_SPECTROMETRY])
		if(MATERIAL_CAP_PIEZOELECTRIC, MATERIAL_CAP_MAGNETOSTRICTIVE, MATERIAL_CAP_REACTIVE_ARMOR, MATERIAL_CAP_SHAPE_MEMORY, MATERIAL_CAP_PHASE_CHANGE)
			return !isnull(batch.test_results[MATERIAL_TEST_MICROSCOPY]) && !isnull(batch.test_results[MATERIAL_TEST_TENSILE])
		if(MATERIAL_CAP_CATALYTIC, MATERIAL_CAP_ANTIMICROBIAL, MATERIAL_CAP_HEMOSTATIC, MATERIAL_CAP_BIOMIMETIC, MATERIAL_CAP_GAS_GETTER, MATERIAL_CAP_POROUS_REAGENT)
			return !isnull(batch.test_results[MATERIAL_TEST_CORROSION]) && !isnull(batch.test_results[MATERIAL_TEST_MICROSCOPY])
		if(MATERIAL_CAP_SCINTILLATING, MATERIAL_CAP_OPTICAL)
			return !isnull(batch.test_results[MATERIAL_TEST_MICROSCOPY]) && !isnull(batch.test_results[MATERIAL_TEST_SPECTROMETRY])
		if(MATERIAL_CAP_RESONANT)
			return !isnull(batch.test_results[MATERIAL_TEST_FIELD])
	return FALSE

/datum/material_batch/proc/material_capability_preview(discovered_only = TRUE)
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
		if(discovered_only && !material_capability_discovered(capability_id, src))
			continue
		result += list(list("id" = capability_id, "name" = material_capability_name(capability_id), "potency" = preview.material_capabilities[capability_id]))
	preview.batch_template = null
	qdel(preview)
	return result

/proc/material_capability_applicable(capability_id, obj/item/item, datum/material/processed_alloy/material)
	var/profile = item.engineered_material_profile
	var/form = material.batch_template?.form
	switch(capability_id)
		if(MATERIAL_CAP_THERMOELECTRIC, MATERIAL_CAP_PIEZOELECTRIC, MATERIAL_CAP_ELECTROGENIC, MATERIAL_CAP_SUPERCONDUCTING, MATERIAL_CAP_RADIOVOLTAIC)
			return istype(item, /obj/item/cell)
		if(MATERIAL_CAP_ANTIMICROBIAL, MATERIAL_CAP_HEMOSTATIC, MATERIAL_CAP_BIOMIMETIC)
			return profile == MATERIAL_APPLICATION_SURGICAL || istype(item, /obj/item/surgical)
		if(MATERIAL_CAP_REACTIVE_ARMOR)
			return istype(item, /obj/item/clothing) || istype(item, /obj/item/material/armor_plating)
		if(MATERIAL_CAP_PHASE_CHANGE)
			return istype(item, /obj/item/clothing) || istype(item, /obj/item/material/armor_plating) || profile == MATERIAL_APPLICATION_PRESSURE
		if(MATERIAL_CAP_GAS_GETTER)
			return form == "sintered stock" || form == "powder" || profile == MATERIAL_APPLICATION_PRESSURE
		if(MATERIAL_CAP_POROUS_REAGENT)
			return profile == MATERIAL_APPLICATION_SURGICAL || profile == MATERIAL_APPLICATION_TOOL || istype(item, /obj/item/material)
		if(MATERIAL_CAP_MAGNETOSTRICTIVE)
			return profile == MATERIAL_APPLICATION_TOOL || istype(item, /obj/item/material)
		if(MATERIAL_CAP_CATALYTIC)
			return profile == MATERIAL_APPLICATION_SURGICAL || profile == MATERIAL_APPLICATION_TOOL || (form in list("electroplated laminate", "sintered stock"))
	return TRUE

/datum/material/proc/dq_apply_material_capabilities(obj/item/item)
	if(!item || !length(material_capabilities) || !istype(src, /datum/material/processed_alloy))
		return
	var/datum/material/processed_alloy/processed = src
	var/list/applicable = list()
	for(var/capability_id in material_capabilities)
		if(material_capability_applicable(capability_id, item, processed))
			applicable[capability_id] = material_capabilities[capability_id]
	if(length(applicable))
		item.AddComponent(/datum/component/material_capabilities, src, applicable)

/datum/component/material_capabilities
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/material_id
	var/list/capabilities
	var/next_activation = 0
	var/next_piezo_activation = 0
	var/reactive_charges = 0
	var/reactive_charge_max = 0
	var/stored_phase_energy = 0
	var/stored_gas_moles = 0
	var/stored_gas_type
	var/catalyst_fouling = 0
	var/last_energy_settlement
	var/reference_temperature
	var/scintillation_timer

/datum/component/material_capabilities/Initialize(datum/material/material, list/applicable)
	. = ..()
	if(!isitem(parent) || !istype(material) || !length(applicable))
		return COMPONENT_INCOMPATIBLE
	material_id = material.name
	capabilities = applicable.Copy()
	if(capability(MATERIAL_CAP_POROUS_REAGENT))
		var/obj/item/item = parent
		item.create_reagents(clamp(round(capability(MATERIAL_CAP_POROUS_REAGENT) / 4), 5, 25))
	if(capability(MATERIAL_CAP_REACTIVE_ARMOR))
		reactive_charge_max = clamp(round(capability(MATERIAL_CAP_REACTIVE_ARMOR) / 20), 1, MATERIAL_CAPABILITY_MAX_CHARGES)
		reactive_charges = reactive_charge_max
	if(capability(MATERIAL_CAP_RADIOVOLTAIC) || capability(MATERIAL_CAP_SCINTILLATING))
		GLOB.material_radiovoltaic_items += parent
	last_energy_settlement = world.time
	reference_temperature = ambient_temperature()

/datum/component/material_capabilities/Destroy(force)
	GLOB.material_radiovoltaic_items -= parent
	if(scintillation_timer)
		deltimer(scintillation_timer)
	capabilities = null
	return ..()

/datum/component/material_capabilities/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_ATOM_TAKE_DAMAGE, PROC_REF(on_take_damage))
	RegisterSignal(parent, COMSIG_ATOM_PRE_EMP_ACT, PROC_REF(on_pre_emp))
	RegisterSignal(parent, COMSIG_ATOM_FIRE_ACT, PROC_REF(on_fire))
	RegisterSignal(parent, COMSIG_ATOM_PROPAGATE_RAD_PULSE, PROC_REF(on_propagated_radiation))
	RegisterSignal(parent, COMSIG_IN_RANGE_OF_IRRADIATION, PROC_REF(on_radiation))
	RegisterSignal(parent, COMSIG_ATOM_ATTACKBY, PROC_REF(on_attackby))
	RegisterSignal(parent, COMSIG_ITEM_ATTACK_SELF, PROC_REF(on_attack_self))
	RegisterSignal(parent, COMSIG_MATERIAL_SURGERY, PROC_REF(on_surgery))

/datum/component/material_capabilities/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EXAMINE, COMSIG_ATOM_TAKE_DAMAGE, COMSIG_ATOM_PRE_EMP_ACT, COMSIG_ATOM_FIRE_ACT, COMSIG_ATOM_PROPAGATE_RAD_PULSE, COMSIG_IN_RANGE_OF_IRRADIATION, COMSIG_ATOM_ATTACKBY, COMSIG_ITEM_ATTACK_SELF, COMSIG_MATERIAL_SURGERY))

/datum/component/material_capabilities/proc/capability(capability_id)
	return capabilities?[capability_id] || 0

/datum/component/material_capabilities/proc/ambient_temperature()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	return air ? air.return_temperature() : T20C

/datum/component/material_capabilities/proc/settle_cell_energy()
	var/obj/item/cell/cell = parent
	if(!istype(cell))
		return 0
	var/now = world.time
	var/elapsed = min(max(now - last_energy_settlement, 0), MATERIAL_CAPABILITY_ENERGY_SETTLE_LIMIT) / 10
	var/generated = capability(MATERIAL_CAP_ELECTROGENIC) * elapsed / 20
	var/current_temperature = ambient_temperature()
	var/thermoelectric = capability(MATERIAL_CAP_THERMOELECTRIC)
	if(thermoelectric && !isnull(reference_temperature))
		generated += thermoelectric * abs(current_temperature - reference_temperature) / 50
	reference_temperature = current_temperature
	last_energy_settlement = now
	return generated > 0 ? cell.give(min(generated, cell.amount_missing())) : 0

/datum/component/material_capabilities/proc/on_examine(datum/source, mob/user, list/examine_text)
	SIGNAL_HANDLER
	settle_cell_energy()
	var/datum/material/processed_alloy/material = get_material_by_name(material_id)
	var/datum/material_batch/batch = material?.batch_template
	var/unqualified_shown = FALSE
	for(var/capability_id in capabilities)
		if(material_capability_discovered(capability_id, batch))
			examine_text += span_notice("Qualified material capability: <b>[material_capability_name(capability_id)]</b> ([capabilities[capability_id]]%).")
		else if(!unqualified_shown)
			examine_text += span_notice("Its material exhibits one or more unqualified anomalous responses.")
			unqualified_shown = TRUE
	if(reactive_charge_max)
		examine_text += span_notice("Reactive reserve: [reactive_charges]/[reactive_charge_max] charges.")
	if(stored_gas_moles > 0)
		examine_text += span_notice("Getter loading: [round(stored_gas_moles, 0.01)]/[round(capability(MATERIAL_CAP_GAS_GETTER) / 5, 0.01)] moles.")
	if(stored_phase_energy > 0)
		examine_text += span_notice("Thermal reservoir: [round(stored_phase_energy)]/[round(phase_capacity())] joules.")
	if(capability(MATERIAL_CAP_CATALYTIC))
		examine_text += span_notice("Catalytic surface loading: [round(catalyst_fouling, 0.01)]/[round(catalyst_capacity(), 0.01)] moles.")

/datum/component/material_capabilities/proc/on_take_damage(datum/source, damage_amount, damage_type, damage_flag, sound_effect, attack_dir, armour_penetration)
	SIGNAL_HANDLER
	if(capability(MATERIAL_CAP_REACTIVE_ARMOR) && reactive_charges > 0 && world.time >= next_activation && damage_amount >= 5)
		reactive_charges--
		next_activation = world.time + MATERIAL_CAPABILITY_COOLDOWN
		new /obj/effect/effect/sparks(get_turf(parent))
		return COMPONENT_NO_TAKE_DAMAGE
	if(capability(MATERIAL_CAP_SHAPE_MEMORY) && ambient_temperature() >= T0C + 80)
		var/obj/item/item = parent
		addtimer(CALLBACK(item, TYPE_PROC_REF(/atom, repair_damage), max(1, round(capability(MATERIAL_CAP_SHAPE_MEMORY) / 20))), 1 SECOND)

/datum/component/material_capabilities/proc/on_pre_emp(datum/source, severity)
	SIGNAL_HANDLER
	if(capability(MATERIAL_CAP_SUPERCONDUCTING) && ambient_temperature() <= T0C)
		return EMP_PROTECT_SELF

/datum/component/material_capabilities/proc/phase_capacity()
	return capability(MATERIAL_CAP_PHASE_CHANGE) * MATERIAL_CAPABILITY_PHASE_JOULES_PER_POTENCY

/datum/component/material_capabilities/proc/absorb_ambient_heat()
	var/remaining = phase_capacity() - stored_phase_energy
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(remaining <= 0 || !air || air.return_temperature() <= T20C)
		return 0
	var/available = max(0, -air.get_thermal_energy_change(T20C))
	var/absorbed = min(remaining, available)
	if(absorbed > 0)
		air.add_thermal_energy(-absorbed)
		stored_phase_energy += absorbed
	return absorbed

/datum/component/material_capabilities/proc/release_stored_heat()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air || stored_phase_energy <= 0)
		return 0
	var/released = stored_phase_energy
	air.add_thermal_energy(released)
	stored_phase_energy = 0
	return released

/datum/component/material_capabilities/proc/on_fire(datum/source, exposed_temperature, exposed_volume)
	SIGNAL_HANDLER
	if(capability(MATERIAL_CAP_PHASE_CHANGE))
		absorb_ambient_heat()
	if(stored_gas_moles > 0 && exposed_temperature >= T0C + 100)
		release_stored_gas()
	if(capability(MATERIAL_CAP_CATALYTIC) && exposed_temperature >= T0C + 300)
		catalyst_fouling = max(0, catalyst_fouling - capability(MATERIAL_CAP_CATALYTIC) / 20)

/datum/component/material_capabilities/proc/on_propagated_radiation(datum/source, atom/pulse_source)
	SIGNAL_HANDLER
	apply_radiation_energy(25)

/datum/component/material_capabilities/proc/on_radiation(datum/source, datum/radiation_pulse_information/pulse_information)
	SIGNAL_HANDLER
	apply_radiation_energy(pulse_information?.strength || 1)

/datum/component/material_capabilities/proc/apply_radiation_energy(strength)
	var/radiovoltaic = capability(MATERIAL_CAP_RADIOVOLTAIC)
	if(radiovoltaic)
		var/obj/item/cell/cell = parent
		if(istype(cell))
			cell.give(max(1, round(radiovoltaic * max(strength, 1) / 100)))
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
	if(!istype(item))
		return
	var/datum/material/material = item.get_material()
	var/base_light = dq_material_luminescence(material)
	if(base_light > 0)
		item.set_light(clamp(base_light / 20, 0.5, 4), clamp(base_light / 30, 0.3, 2), material.icon_colour)
	else
		item.set_light(0)

/datum/component/material_capabilities/proc/on_attackby(datum/source, obj/item/weapon, mob/living/user, list/modifiers)
	SIGNAL_HANDLER
	if(reactive_charge_max && reactive_charges < reactive_charge_max && istype(weapon, /obj/item/cell))
		var/obj/item/cell/cell = weapon
		if(cell.checked_use(MATERIAL_CAPABILITY_REACTIVE_CHARGE_ENERGY))
			reactive_charges++
			if(user)
				to_chat(user, span_notice("You recharge one reactive cell in [parent]."))
		else
			if(user)
				to_chat(user, span_warning("[cell] cannot supply the required [MATERIAL_CAPABILITY_REACTIVE_CHARGE_ENERGY] units."))
		return
	if(!capability(MATERIAL_CAP_POROUS_REAGENT) || !weapon?.reagents?.total_volume)
		return
	var/obj/item/item = parent
	var/transferred = weapon.reagents.trans_to(item, min(5, weapon.reagents.total_volume))
	if(transferred)
		to_chat(user, span_notice("The porous lattice absorbs [transferred] units from [weapon]."))

/datum/component/material_capabilities/proc/on_form_trigger(condition, turf/where, atom/cause)
	if(condition != SUB_TRIG_IMPACT)
		return
	var/obj/item/item = parent
	var/piezoelectric = capability(MATERIAL_CAP_PIEZOELECTRIC)
	if(piezoelectric && world.time >= next_piezo_activation)
		var/obj/item/cell/cell = istype(item, /obj/item/cell) ? item : item.get_cell()
		var/impact_force = max(item.force, item.throwforce)
		if(cell && impact_force > 0)
			next_piezo_activation = world.time + MATERIAL_CAPABILITY_PIEZO_COOLDOWN
			cell.give(max(1, round(piezoelectric * impact_force / 100)))
	if(capability(MATERIAL_CAP_POROUS_REAGENT) && item.reagents?.total_volume && isliving(cause))
		item.reagents.trans_to(cause, min(2, item.reagents.total_volume))

/datum/component/material_capabilities/proc/on_attack_self(datum/source, mob/living/user)
	SIGNAL_HANDLER
	INVOKE_ASYNC(src, PROC_REF(choose_activation), user)

/datum/component/material_capabilities/proc/activation_options()
	var/list/options = list()
	if(capability(MATERIAL_CAP_MAGNETOSTRICTIVE)) options += "Magnetic retrieval pulse"
	if(capability(MATERIAL_CAP_RESONANT)) options += "Survey matching material"
	if(capability(MATERIAL_CAP_OPTICAL)) options += "Toggle optical response"
	if(capability(MATERIAL_CAP_GAS_GETTER) && stored_gas_moles <= 0) options += "Capture hazardous gas"
	if(stored_gas_moles > 0) options += "Release captured gas"
	if(capability(MATERIAL_CAP_CATALYTIC)) options += "Catalyze contaminated air"
	if(capability(MATERIAL_CAP_PHASE_CHANGE))
		options += "Absorb ambient heat"
		if(stored_phase_energy > 0) options += "Release stored heat"
	return options

/datum/component/material_capabilities/proc/choose_activation(mob/living/user)
	var/list/options = activation_options()
	if(!length(options))
		return
	var/choice = length(options) == 1 ? options[1] : tgui_input_list(user, "Select the material response to excite.", "Material response", options)
	if(!choice || QDELETED(parent) || !user || get_dist(user, parent) > 1 || world.time < next_activation)
		return
	next_activation = world.time + MATERIAL_CAPABILITY_COOLDOWN
	switch(choice)
		if("Magnetic retrieval pulse")
			activate_magnetostriction(user)
		if("Survey matching material")
			activate_resonance(user)
		if("Toggle optical response")
			var/obj/item/item = parent
			item.alpha = item.alpha < 255 ? 255 : 110
			to_chat(user, span_notice("The optical lattice [item.alpha < 255 ? "bends light around itself" : "returns to its opaque state"]."))
		if("Capture hazardous gas")
			capture_hazardous_gas(user)
		if("Release captured gas")
			release_stored_gas()
		if("Catalyze contaminated air")
			activate_catalyst(user)
		if("Absorb ambient heat")
			var/absorbed = absorb_ambient_heat()
			to_chat(user, span_notice("The phase reservoir absorbs [round(absorbed)] joules."))
		if("Release stored heat")
			var/released = release_stored_heat()
			to_chat(user, span_notice("The phase reservoir releases [round(released)] joules."))

/datum/component/material_capabilities/proc/activate_magnetostriction(mob/living/user)
	var/moved = 0
	for(var/obj/item/other in range(7, user))
		var/datum/material/other_material = other.get_material()
		if(other == parent || other.anchored || other_material?.name != material_id || other.w_class > ITEMSIZE_NORMAL)
			continue
		other.throw_at(user, 7, 2, user)
		moved++
		if(moved >= max(1, round(capability(MATERIAL_CAP_MAGNETOSTRICTIVE) / 20)))
			break
	if(moved)
		user.visible_message(span_notice("[parent] emits a magnetic retrieval pulse."))
	else
		to_chat(user, span_notice("No movable matching material answers the pulse."))

/datum/component/material_capabilities/proc/activate_resonance(mob/living/user)
	var/list/findings = list()
	for(var/obj/item/other in range(10, user))
		var/datum/material/other_material = other.get_material()
		if(other != parent && other_material?.name == material_id)
			findings += "[other] ([get_dist(user, other)] tiles [dir2text(get_dir(user, other))])"
	to_chat(user, span_notice(length(findings) ? "The resonant response locates [jointext(findings, ", ")]." : "No matching material answers the resonance pulse."))

/datum/component/material_capabilities/proc/capture_hazardous_gas(mob/living/user)
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air)
		return
	var/capacity = capability(MATERIAL_CAP_GAS_GETTER) / 5
	for(var/gas_path in list(/datum/gas/plasma, /datum/gas/miasma, /datum/gas/carbon_dioxide))
		var/available = air.get_moles(gas_path)
		if(available <= 0.01)
			continue
		var/take = min(available, capacity)
		air.adjust_moles(gas_path, -take)
		stored_gas_type = gas_path
		stored_gas_moles = take
		var/list/gas_info = GLOB.meta_gas_info[gas_path]
		if(user)
			to_chat(user, span_notice("The getter lattice captures [round(take, 0.01)] moles of [gas_info[META_GAS_NAME]]."))
		return
	if(user)
		to_chat(user, span_notice("The getter finds no supported contaminant to capture."))

/datum/component/material_capabilities/proc/activate_catalyst(mob/living/user)
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air)
		return
	var/miasma = air.get_moles(/datum/gas/miasma)
	var/converted = min(miasma, capability(MATERIAL_CAP_CATALYTIC) / 100, catalyst_capacity() - catalyst_fouling)
	if(converted <= 0.001)
		if(user)
			to_chat(user, span_notice("The catalytic surface detects no miasma."))
		return
	air.adjust_moles(/datum/gas/miasma, -converted)
	air.adjust_moles(/datum/gas/carbon_dioxide, converted)
	catalyst_fouling += converted
	if(user)
		to_chat(user, span_notice("The catalytic surface oxidizes [round(converted, 0.01)] moles of contamination into carbon dioxide."))

/datum/component/material_capabilities/proc/catalyst_capacity()
	return capability(MATERIAL_CAP_CATALYTIC) / 10

/datum/component/material_capabilities/proc/release_stored_gas()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air || !stored_gas_type || stored_gas_moles <= 0)
		return 0
	var/released = stored_gas_moles
	air.adjust_moles(stored_gas_type, released)
	stored_gas_moles = 0
	stored_gas_type = null
	return released

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
	var/datum/component/material_capabilities/component = GetComponent(/datum/component/material_capabilities)
	component?.settle_cell_energy()
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
		new /obj/effect/effect/sparks(get_turf(src))
		return amount * 1.5
	return amount
