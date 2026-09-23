/// Operating roles extend the existing pressure construction; they are only
/// present on devices with a motor and moving gas-working surfaces.
/// Pump devices declare the pump template; this upgrades a pressure device that
/// gains a drive at runtime. Its pressure-envelope overrides carry over, and the
/// drive train adds three sheets to its total.
/obj/machinery/proc/ensure_pump_materials(notify = TRUE)
	if(material_template == /datum/material_template/pump)
		return
	var/list/kept_overrides = material_overrides
	material_total = get_material_total() + 3 * SHEET_MATERIAL_AMOUNT
	material_template = /datum/material_template/pump
	material_overrides = kept_overrides
	if(notify)
		material_service_changed()

/obj/machinery/proc/material_pump_efficiency()
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	var/datum/material/bearings = material_for_role(MATERIAL_ROLE_BEARINGS)
	var/datum/material/reference = get_material_by_name(MAT_COPPER)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/electrical = conductor ? conductor.conductivity / max(reference.conductivity, 1) : 1
	var/mechanical = bearings ? (bearings.hardness + bearings.elasticity) / max(steel.hardness + steel.elasticity, 1) : 1
	return clamp(0.8 * sqrt(max(electrical * mechanical, 0)), 0.05, 0.95)

/obj/machinery/proc/material_pump_power(rated_power)
	if(isnull(rated_power))
		return null
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	var/datum/material/working = material_for_role(MATERIAL_ROLE_WORKING)
	var/datum/material/copper = get_material_by_name(MAT_COPPER)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/motor = conductor ? conductor.conductivity / max(copper.conductivity, 1) : 1
	var/impeller = working ? working.yield_strength / max(steel.yield_strength, 1) : 1
	var/thermal = material_service ? clamp((0.95 - material_service.last_stress) / 0.15, 0, 1) : 1
	var/available = rated_power * clamp(min(motor, impeller), 0.1, 2.5) * thermal
	if(istype(src, /obj/machinery/portable_atmospherics/powered))
		var/obj/machinery/portable_atmospherics/powered/portable = src
		if(portable.use_cell && !portable.use_power)
			available = min(available, portable.cell ? max(0, portable.cell.material_available_output((available + portable.power_losses) * CELLRATE) / CELLRATE - portable.power_losses) : 0)
	return available

/obj/machinery/proc/material_service_work_rating()
	return 0

/obj/machinery/atmospherics/material_service_work_rating()
	return power_rating

/obj/machinery/portable_atmospherics/powered/proc/pay_material_pump_energy(pump_energy)
	var/paid = cell ? cell.use(max(pump_energy, power_losses) * CELLRATE) / CELLRATE : 0
	// Compression and its motor losses were accounted at the gas transfer.
	// The remaining idle-drive draw becomes heat, never additional gas work.
	if(paid > pump_energy && material_service)
		material_service.record_work(paid - pump_energy, 0)
	return paid

/obj/machinery/proc/record_material_pumping(input_energy, datum/gas_mixture/destination, actual_moles)
	if(input_energy <= 0 || actual_moles <= 0)
		return
	var/useful = input_energy * material_pump_efficiency()
	var/rated = material_pump_power(material_service_work_rating())
	material_service_event(MATERIAL_EVENT_WORK, rated > 0 ? input_energy / rated : 0)
	var/turf/environment_turf = get_turf(src)
	var/datum/gas_mixture/environment = environment_turf ? environment_turf.return_air() : null
	for(var/datum/gas_mixture/air as anything in material_service_gases())
		material_observe_gases(air, environment)
	if(!material_service)
		return
	// Transferring gas preserves its existing thermal energy, but compression
	// work is new energy supplied by the motor. Deposit useful shaft work into
	// the destination gas and motor losses into the shell so the complete
	// machine + gas ledger conserves exactly the power paid by the pump.
	destination.add_thermal_energy(useful)
	material_service.record_work(input_energy, useful)
	material_service.delivered_moles += actual_moles
	material_service.last_delivery_pressure = destination.return_pressure()
	material_service.last_delivery_temperature = destination.return_temperature()
	material_service.last_delivery_mixture = WEAKREF(destination)

/datum/material_service
	var/delivered_moles = 0
	var/last_delivery_pressure = 0
	var/last_delivery_temperature = 0
	var/datum/weakref/last_delivery_mixture
	var/last_work_time = 0
	var/last_work_kind
	var/last_work_duration = 0

/datum/material_service/proc/record_work(input_energy, useful_energy, elapsed = 1)
	input_energy = max(input_energy, 0)
	useful_energy = clamp(useful_energy, 0, input_energy)
	input_joules += input_energy
	output_joules += useful_energy
	loss_joules += input_energy - useful_energy
	last_input_watts = input_energy / max(elapsed, 0.1)
	last_output_watts = useful_energy / max(elapsed, 0.1)
	last_work_time = world.time
	last_work_duration = elapsed
	add_heat(input_energy - useful_energy)

/obj/machinery/atmospherics/binary/pump/material_service_rating()
	return max_pressure_setting

/obj/machinery/power/emitter
	var/material_output_setting = 1
	var/material_cadence_setting = 1
	var/material_stored_energy = 0
	var/material_last_charge
	var/material_beam_joules = 0

/obj/machinery/power/emitter/proc/emitter_efficiency()
	var/datum/material/element = material_for_role(MATERIAL_ROLE_EMITTER)
	var/datum/material/optics = material_for_role(MATERIAL_ROLE_OPTICAL)
	var/datum/material/reference = get_material_by_name(MAT_GLASS)
	if(!element || !optics)
		return 0.8
	var/factor = (element.purity_equivalent() + optics.purity_equivalent()) / max(reference.purity_equivalent() * 2, 1)
	return clamp(0.8 * factor, 0.1, 0.97)

/obj/machinery/power/emitter/proc/emitter_output_limit()
	var/datum/material/element = material_for_role(MATERIAL_ROLE_EMITTER)
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	var/datum/material/reference = get_material_by_name(MAT_GLASS)
	var/datum/material/copper = get_material_by_name(MAT_COPPER)
	var/optical_limit = element ? element.melting_point / max(reference.melting_point, 1) : 1
	var/electrical_limit = conductor ? conductor.conductivity / max(copper.conductivity, 1) : 1
	var/thermal_limit = material_service ? clamp((0.95 - material_service.last_stress) / 0.15, 0, 1) : 1
	return clamp(min(optical_limit, electrical_limit), 0.1, 3) * thermal_limit

/obj/machinery/power/emitter/proc/charge_emitter()
	var/elapsed = isnull(material_last_charge) ? 0 : max(world.time - material_last_charge, 0) / 10
	material_last_charge = world.time
	if(elapsed <= 0)
		return
	var/limit = emitter_output_limit()
	var/request = active_power_usage * min(material_output_setting, limit) / emitter_efficiency()
	var/actual = draw_power(request)
	var/input_energy = actual * elapsed
	var/stored = min(input_energy, max(active_power_usage * 10 - material_stored_energy, 0))
	material_stored_energy += stored
	// A live accelerator beam is intrinsically high-energy work, independent of
	// the concrete machine type or whether its component materials are standard.
	material_service_event(MATERIAL_EVENT_WORK, actual > 0 ? 1.25 : 0)
	if(!material_service)
		return
	material_service.input_joules += input_energy
	material_service.loss_joules += input_energy - stored
	material_service.last_input_watts = actual
	material_service.add_heat(input_energy - stored)
	if(limit < material_output_setting)
		material_service.limiting_role = "Emitter temperature or installed electrical/optical parts"
	else
		material_service.limiting_role = null
