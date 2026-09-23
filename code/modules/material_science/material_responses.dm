/// Event-driven physical responses for manufactured material forms. There is
/// deliberately no capability/tag list and no activation menu: each response
/// follows from a numeric material coefficient, the product geometry, and a
/// real event such as impact, radiation, heat, surgery, or reagent contact.

GLOBAL_LIST_EMPTY(material_radiovoltaic_items)

/datum/material/proc/dq_apply_material_responses(obj/item/item)
	if(!item)
		return
	var/profile = item.engineered_material_profile
	var/electrical_form = istype(item, /obj/item/cell)
	var/medical_form = profile == MATERIAL_APPLICATION_SURGICAL || istype(item, /obj/item/surgical)
	var/armor_form = profile == MATERIAL_APPLICATION_ARMOR || istype(item, /obj/item/clothing) || istype(item, /obj/item/material/armor_plating)
	var/tool_form = profile == MATERIAL_APPLICATION_TOOL || istype(item, /obj/item/material)
	var/needs_response = \
		(electrical_form && (thermoelectric_coefficient || piezoelectric_coefficient || electrogenic_rate || radiovoltaic_efficiency || scintillation_efficiency || critical_temperature)) || \
		(medical_form && (antimicrobial_activity || hemostatic_activity || biocompatibility || reagent_porosity)) || \
		(armor_form && (reactive_energy_capacity || shape_recovery_rate || phase_change_capacity)) || \
		(tool_form && (shape_recovery_rate || piezoelectric_coefficient || reagent_porosity))
	var/datum/component/material_response/existing = item.GetComponent(/datum/component/material_response)
	if(existing)
		// Reconfiguration changes the source material without replacing the
		// component and refilling its stored energy reservoirs.
		existing.material_id = name
		existing.electrical_form = electrical_form
		existing.medical_form = medical_form
		existing.armor_form = armor_form
		existing.tool_form = tool_form
		existing.stored_reactive_energy = min(existing.stored_reactive_energy, reactive_energy_capacity)
		GLOB.material_radiovoltaic_items -= item
		if(electrical_form && (radiovoltaic_efficiency || scintillation_efficiency))
			GLOB.material_radiovoltaic_items |= item
	else if(needs_response)
		item.AddComponent(/datum/component/material_response, src, electrical_form, medical_form, armor_form, tool_form)

/datum/component/material_response
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/material_id
	var/electrical_form = FALSE
	var/medical_form = FALSE
	var/armor_form = FALSE
	var/tool_form = FALSE
	var/last_energy_settlement
	var/reference_temperature
	var/next_piezo_response = 0
	var/stored_phase_energy = 0
	var/stored_reactive_energy = 0
	var/scintillation_timer

/datum/component/material_response/Initialize(datum/material/material, _electrical_form, _medical_form, _armor_form, _tool_form)
	. = ..()
	if(!isitem(parent) || !istype(material))
		return COMPONENT_INCOMPATIBLE
	material_id = material.name
	electrical_form = !!_electrical_form
	medical_form = !!_medical_form
	armor_form = !!_armor_form
	tool_form = !!_tool_form
	last_energy_settlement = world.time
	reference_temperature = ambient_temperature()
	stored_reactive_energy = armor_form ? material.reactive_energy_capacity : 0
	if(material.reagent_porosity > 0 && (medical_form || tool_form))
		var/obj/item/item = parent
		item.create_reagents(material.reagent_porosity)
	if(electrical_form && (material.radiovoltaic_efficiency > 0 || material.scintillation_efficiency > 0))
		GLOB.material_radiovoltaic_items += parent

/datum/component/material_response/Destroy(force)
	GLOB.material_radiovoltaic_items -= parent
	if(scintillation_timer)
		deltimer(scintillation_timer)
		scintillation_timer = null
	return ..()

/datum/component/material_response/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_ATOM_TAKE_DAMAGE, PROC_REF(on_take_damage))
	RegisterSignal(parent, COMSIG_ATOM_PRE_EMP_ACT, PROC_REF(on_pre_emp))
	RegisterSignal(parent, COMSIG_ATOM_FIRE_ACT, PROC_REF(on_fire))
	RegisterSignal(parent, COMSIG_ATOM_PROPAGATE_RAD_PULSE, PROC_REF(on_propagated_radiation))
	RegisterSignal(parent, COMSIG_IN_RANGE_OF_IRRADIATION, PROC_REF(on_radiation))
	RegisterSignal(parent, COMSIG_ATOM_ATTACKBY, PROC_REF(on_attackby))
	RegisterSignal(parent, COMSIG_MATERIAL_SURGERY, PROC_REF(on_surgery))

/datum/component/material_response/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EXAMINE, COMSIG_ATOM_TAKE_DAMAGE, COMSIG_ATOM_PRE_EMP_ACT, COMSIG_ATOM_FIRE_ACT, COMSIG_ATOM_PROPAGATE_RAD_PULSE, COMSIG_IN_RANGE_OF_IRRADIATION, COMSIG_ATOM_ATTACKBY, COMSIG_MATERIAL_SURGERY))

/datum/component/material_response/proc/material() as /datum/material
	return get_material_by_name(material_id)

/datum/component/material_response/proc/ambient_temperature()
	var/obj/assembly = parent
	if(assembly.material_service)
		return assembly.material_service.current_temperature()
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	return air ? air.return_temperature() : T20C

/datum/component/material_response/proc/settle_cell_energy()
	var/obj/item/cell/cell = parent
	var/datum/material/material = material()
	if(!electrical_form || !istype(cell) || !material)
		return 0
	var/now = world.time
	var/elapsed_seconds = min(max(now - last_energy_settlement, 0), 5 MINUTES) / 10
	var/current_temperature = ambient_temperature()
	var/generated = material.electrogenic_rate * elapsed_seconds
	// Thermoelectric conversion is applied to real transferred heat by the
	// assembly thermal service, never to a difference between UI observations.
	reference_temperature = current_temperature
	last_energy_settlement = now
	return generated > 0 ? cell.give(min(generated, cell.amount_missing())) : 0

/datum/component/material_response/proc/on_examine(datum/source, mob/user, list/examine_text)
	SIGNAL_HANDLER
	settle_cell_energy()
	var/datum/material/material = material()
	if(!material)
		return
	var/list/responses = material.material_response_summary()
	if(length(responses))
		examine_text += span_notice("Physical responses: [jointext(responses, "; ")].")
	if(material.reactive_energy_capacity > 0 && armor_form)
		examine_text += span_notice("Reactive layer energy: [round(stored_reactive_energy)]/[round(material.reactive_energy_capacity)] J.")
	if(material.phase_change_capacity > 0 && armor_form)
		examine_text += span_notice("Thermal buffer: [round(stored_phase_energy)]/[round(material.phase_change_capacity)] J.")

/datum/component/material_response/proc/on_take_damage(datum/source, damage_amount, damage_type, damage_flag, sound_effect, attack_dir, armour_penetration)
	SIGNAL_HANDLER
	var/datum/material/material = material()
	if(!material)
		return
	if(material.shape_recovery_rate > 0 && ambient_temperature() >= material.shape_recovery_temperature)
		var/obj/item/item = parent
		addtimer(CALLBACK(item, TYPE_PROC_REF(/atom, repair_damage), max(1, round(material.shape_recovery_rate))), 1 SECOND)

/datum/component/material_response/proc/on_pre_emp(datum/source, severity)
	SIGNAL_HANDLER
	var/datum/material/material = material()
	if(electrical_form && material?.critical_temperature > 0 && ambient_temperature() < material.critical_temperature)
		return EMP_PROTECT_SELF

/datum/component/material_response/proc/on_fire(datum/source, exposed_temperature, exposed_volume)
	SIGNAL_HANDLER
	var/datum/material/material = material()
	if(!material || !armor_form || material.phase_change_capacity <= 0)
		return
	var/turf/turf = get_turf(parent)
	var/datum/gas_mixture/air = turf?.return_air()
	if(!air)
		return
	var/remaining = material.phase_change_capacity - stored_phase_energy
	if(remaining > 0 && air.return_temperature() > material.phase_change_temperature)
		var/available = max(0, -air.get_thermal_energy_change(material.phase_change_temperature))
		var/absorbed = min(remaining, available)
		air.add_thermal_energy(-absorbed)
		stored_phase_energy += absorbed

/datum/component/material_response/proc/on_propagated_radiation(datum/source, atom/pulse_source)
	SIGNAL_HANDLER
	apply_radiation_energy(25)

/datum/component/material_response/proc/on_radiation(datum/source, datum/radiation_pulse_information/pulse_information)
	SIGNAL_HANDLER
	apply_radiation_energy(pulse_information?.strength || 1)

/datum/component/material_response/proc/apply_radiation_energy(strength)
	var/datum/material/material = material()
	if(!material || !electrical_form)
		return
	var/obj/item/cell/cell = parent
	if(material.radiovoltaic_efficiency > 0 && istype(cell))
		cell.give(max(1, round(material.radiovoltaic_efficiency * max(strength, 1))))
	if(material.scintillation_efficiency > 0)
		var/obj/item/item = parent
		item.set_light(clamp(material.scintillation_efficiency * 5, 0.5, 5), clamp(material.scintillation_efficiency * 3, 0.3, 3), "#88ddff")
		if(scintillation_timer)
			deltimer(scintillation_timer)
		scintillation_timer = addtimer(CALLBACK(src, PROC_REF(end_scintillation)), 5 SECONDS, TIMER_STOPPABLE)

/datum/component/material_response/proc/end_scintillation()
	scintillation_timer = null
	var/obj/item/item = parent
	var/datum/material/material = material()
	if(!istype(item) || !material)
		return
	var/base_light = dq_material_luminescence(material)
	if(base_light > 0)
		item.set_light(clamp(base_light / 20, 0.5, 4), clamp(base_light / 30, 0.3, 2), material.icon_colour)
	else
		item.set_light(0)

/datum/component/material_response/proc/on_attackby(datum/source, obj/item/weapon, mob/living/user, list/modifiers)
	SIGNAL_HANDLER
	var/datum/material/material = material()
	if(!material)
		return
	if(armor_form && material.reactive_energy_capacity > 0 && stored_reactive_energy < material.reactive_energy_capacity && istype(weapon, /obj/item/cell))
		var/obj/item/cell/cell = weapon
		var/needed = material.reactive_energy_capacity - stored_reactive_energy
		var/taken = min(needed, cell.charge)
		if(taken > 0)
			cell.use(taken)
			stored_reactive_energy += taken
			to_chat(user, span_notice("You discharge [round(taken)] units from [cell] into [parent]'s reactive layer."))
		return
	if(material.reagent_porosity <= 0 || !(medical_form || tool_form) || !weapon?.reagents?.total_volume)
		return
	var/obj/item/item = parent
	var/transferred = weapon.reagents.trans_to(item, min(5, weapon.reagents.total_volume))
	if(transferred)
		to_chat(user, span_notice("[parent]'s open pores absorb [transferred] units from [weapon]."))

/datum/component/material_response/proc/respond_to_impact(atom/cause)
	var/datum/material/material = material()
	var/obj/item/item = parent
	if(!material || !istype(item))
		return
	if(electrical_form && material.piezoelectric_coefficient > 0 && world.time >= next_piezo_response)
		var/obj/item/cell/cell = istype(item, /obj/item/cell) ? item : item.get_cell()
		var/impact_force = max(item.force, item.throwforce)
		if(cell && impact_force > 0)
			next_piezo_response = world.time + 1 SECOND
			cell.give(max(1, round(material.piezoelectric_coefficient * impact_force)))
	if(material.reagent_porosity > 0 && item.reagents?.total_volume && isliving(cause))
		item.reagents.trans_to(cause, min(2, item.reagents.total_volume))

/datum/component/material_response/proc/on_surgery(datum/source, mob/living/carbon/human/target, target_zone, successful)
	SIGNAL_HANDLER
	if(!successful || !medical_form || !istype(target))
		return
	var/datum/material/material = material()
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!material || !affected)
		return
	if(material.antimicrobial_activity > 0)
		affected.germ_level = max(0, affected.germ_level - material.antimicrobial_activity * 2)
		target.germ_level = max(0, target.germ_level - material.antimicrobial_activity)
	if(material.hemostatic_activity >= 50)
		affected.organ_clamp()
		for(var/datum/affliction/wound/internal_bleeding/wound in affected.get_wounds())
			wound.clamped = TRUE
	if(material.biocompatibility > 0 && affected.get_trauma() + affected.get_burn() > 0)
		target.mend(TREAT_TISSUE_REPAIR, max(1, round(material.biocompatibility / 20)), target_zone)

/datum/component/material_response/proc/absorb_reactive_hit(damage)
	if(!armor_form || damage <= 0 || stored_reactive_energy <= 0)
		return FALSE
	var/energy_cost = damage * 50
	if(stored_reactive_energy < energy_cost)
		return FALSE
	stored_reactive_energy -= energy_cost
	new /obj/effect/effect/sparks(get_turf(parent))
	return TRUE

/datum/material/proc/material_response_summary()
	var/list/result = list()
	if(critical_temperature > 0) result += "superconducts below [round(critical_temperature)] K"
	if(phase_change_capacity > 0 && phase_change_temperature > 0) result += "buffers [round(phase_change_capacity)] J near [round(phase_change_temperature)] K"
	if(thermoelectric_coefficient > 0) result += "thermoelectric [round(thermoelectric_coefficient, 0.01)]"
	if(piezoelectric_coefficient > 0) result += "piezoelectric [round(piezoelectric_coefficient, 0.01)]"
	if(electrogenic_rate > 0) result += "generates [round(electrogenic_rate, 0.1)] charge/s"
	if(radiovoltaic_efficiency > 0) result += "radiovoltaic [round(radiovoltaic_efficiency, 0.01)]"
	if(field_energy_capacity > 0) result += "stores [round(field_energy_capacity)] units of deposited field energy"
	if(exothermic_heat_rate > 0) result += "releases [round(exothermic_heat_rate)] J/s as heat"
	if(heat_pump_coefficient > 0) result += "heat-pump coefficient [round(heat_pump_coefficient, 0.01)]"
	if(thermal_switch_temperature > 0) result += "opens a thermal path above [round(thermal_switch_temperature)] K"
	if(shape_recovery_rate > 0) result += "recovers above [round(shape_recovery_temperature)] K"
	if(reactive_energy_capacity > 0) result += "stores [round(reactive_energy_capacity)] J reactive energy"
	if(catalytic_activity > 0) result += "catalytic surface [round(catalytic_activity)]"
	if(antimicrobial_activity > 0) result += "antimicrobial [round(antimicrobial_activity)]"
	if(hemostatic_activity > 0) result += "hemostatic [round(hemostatic_activity)]"
	if(biocompatibility > 0) result += "biocompatible [round(biocompatibility)]"
	if(gas_sorption_capacity > 0) result += "sorbs [round(gas_sorption_capacity, 0.1)] mol gas"
	if(reagent_porosity > 0) result += "holds [round(reagent_porosity, 0.1)]u reagent"
	return result

/obj/item/proc/material_response_impact(turf/where, atom/cause)
	var/datum/component/material_response/component = GetComponent(/datum/component/material_response)
	component?.respond_to_impact(cause)

/obj/item/proc/material_reactive_absorb(damage)
	var/datum/component/material_response/component = GetComponent(/datum/component/material_response)
	return component?.absorb_reactive_hit(damage) || FALSE

/obj/item/proc/material_cell_use_cost(amount)
	var/datum/component/material_response/component = GetComponent(/datum/component/material_response)
	component?.settle_cell_energy()
	// Superconductors eliminate conductor loss; they do not multiply stored
	// energy. Throughput and heat are handled by the cell's conductor role.
	return amount
