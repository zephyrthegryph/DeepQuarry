// A multitool observes an assembly while the operator remains beside it.
// Reports travel in the tool's memory and are printed by an existing copier.
/obj/item/multitool
	var/list/engineering_reading
	var/engineering_evidence_id

/datum/material_service
	var/datum/weakref/monitor_tool
	var/datum/weakref/monitor_user
	var/monitor_last_input = 0
	var/monitor_last_output = 0
	var/monitor_last_moles = 0
	var/monitor_last_time = 0
	var/monitor_configuration = -1
	var/maintenance_open = FALSE
	var/last_reading_id
	var/list/last_reading
	var/monitor_started = 0
	var/monitor_input = 0
	var/monitor_output = 0
	var/monitor_moles = 0
	var/monitor_minimum_output = INFINITY
	var/monitor_minimum_flow = INFINITY
	var/monitor_maximum_temperature = 0
	var/monitor_minimum_pressure = INFINITY
	var/monitor_stored_energy = 0

/datum/material_service/proc/register_diagnostics()
	RegisterSignal(owner, COMSIG_ATOM_SECONDARY_TOOL_ACT(TOOL_MULTITOOL), PROC_REF(inspect_with_tool))
	RegisterSignal(owner, COMSIG_ATOM_SECONDARY_TOOL_ACT(TOOL_SCREWDRIVER), PROC_REF(open_service_cover))
	RegisterSignal(owner, COMSIG_ATOM_ATTACKBY, PROC_REF(replace_with_stock))
	RegisterSignal(owner, COMSIG_ATOM_EXAMINE, PROC_REF(examine_service))

/datum/material_service/proc/unregister_diagnostics()
	UnregisterSignal(owner, list(COMSIG_ATOM_SECONDARY_TOOL_ACT(TOOL_MULTITOOL), COMSIG_ATOM_SECONDARY_TOOL_ACT(TOOL_SCREWDRIVER), COMSIG_ATOM_ATTACKBY, COMSIG_ATOM_EXAMINE))
	monitor_tool = null
	monitor_user = null
	last_reading = null

/datum/material_service/proc/examine_service(datum/source, mob/user, list/text)
	SIGNAL_HANDLER
	text += span_notice("[summary()] Right-click with a multitool to measure operation; right-click with a screwdriver to open the service cover.")
	if(maintenance_open)
		text += span_notice("The service cover is open. Replacement material stock can be fitted to an individual component.")

/datum/material_service/proc/can_service(mob/user)
	if(!owner || QDELETED(owner) || !user || !user.Adjacent(owner) || user.incapacitated())
		return FALSE
	if(ismachinery(owner))
		var/obj/machinery/machine = owner
		if(!machine.allowed(user))
			return FALSE
	if(istype(owner, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/emitter = owner
		if(emitter.active)
			return FALSE
	return TRUE

/datum/material_service/proc/inspect_with_tool(datum/source, mob/user, obj/item/tool)
	SIGNAL_HANDLER
	if(!user.Adjacent(owner) || !istype(tool, /obj/item/multitool))
		return ITEM_INTERACT_BLOCKING
	monitor_tool = WEAKREF(tool)
	monitor_user = WEAKREF(user)
	monitor_last_input = input_joules
	monitor_last_output = output_joules
	monitor_last_moles = delivered_moles
	monitor_last_time = world.time
	monitor_configuration = owner.material_configuration_revision
	reset_observation()
	schedule(0)
	INVOKE_ASYNC(src, PROC_REF(tgui_interact), user)
	return ITEM_INTERACT_SUCCESS

/datum/material_service/proc/open_service_cover(datum/source, mob/user, obj/item/tool)
	SIGNAL_HANDLER
	if(!can_service(user))
		to_chat(user, span_warning("The assembly must be accessible and stopped before opening its service cover."))
		return ITEM_INTERACT_BLOCKING
	maintenance_open = !maintenance_open
	owner.visible_message(span_notice("[user] [maintenance_open ? "opens" : "closes"] [owner]'s service cover."))
	return ITEM_INTERACT_SUCCESS

/datum/material_service/proc/replace_with_stock(datum/source, obj/item/item, mob/user, list/modifiers)
	SIGNAL_HANDLER
	if(!maintenance_open || !istype(item, /obj/item/stack/material))
		return NONE
	INVOKE_ASYNC(src, PROC_REF(fit_stock), item, user)
	return COMPONENT_CANCEL_ATTACK_CHAIN

/datum/material_service/proc/fit_stock(obj/item/stack/material/stock, mob/user)
	if(!can_service(user) || !stock || stock.loc != user)
		return
	var/list/roles = list()
	for(var/role in owner.construction_materials)
		roles += role
	var/role = tgui_input_list(user, "Which component should be replaced?", "Service assembly", roles)
	if(!role || !can_service(user) || !maintenance_open || QDELETED(stock) || stock.loc != user || !(role in owner.construction_materials))
		return
	var/quantity = max(1, CEILING((owner.construction_material_amounts?[role] || SHEET_MATERIAL_AMOUNT) / SHEET_MATERIAL_AMOUNT, 1))
	if(stock.get_amount() < quantity)
		to_chat(user, span_warning("This component requires [quantity] sheets."))
		return
	var/material_id = stock.get_material_name()
	if(!do_after(user, 2 SECONDS, target = owner) || !can_service(user) || !maintenance_open || QDELETED(stock) || stock.loc != user || !stock.use(quantity))
		return
	advance()
	if(QDELETED(owner))
		return
	owner.construction_materials[role] = material_id
	if(role == MATERIAL_ROLE_LINER)
		owner.material_environment_liner_integrity = 100
	if(role == MATERIAL_ROLE_STRUCTURE)
		owner.material_environment_exterior_integrity = 100
		owner.material_environment_fatigue = 0
	if(owner.material_environment_liner_integrity > 0 && owner.material_environment_exterior_integrity > 0 && owner.material_environment_fatigue < 100)
		owner.material_environment_leaking = FALSE
		owner.material_environment_repaired()
	owner.material_service_changed()
	if(isitem(owner))
		var/obj/item/item = owner
		item.apply_material_role_effects(item.engineered_material_profile)
	if(istype(owner, /obj/structure/cable))
		var/obj/structure/cable/cable = owner
		cable.powernet?.invalidate_material_cache()
	owner.visible_message(span_notice("[user] fits a new [role] into [owner]."))
	contents_changed()

/datum/material_service/tgui_host(mob/user)
	return owner

/datum/material_service/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "EngineeringAssembly", "[owner.name] — diagnostics")
		ui.open()

/datum/material_service/tgui_data(mob/user)
	var/list/parts = list()
	for(var/role in owner.construction_materials)
		var/datum/material/material = owner.material_for_role(role)
		parts += list(list("role" = role, "material" = material.display_name || material.name, "meltingPoint" = material.melting_point, "corrosion" = material.corrosion_resistance))
	var/list/data = list("status" = status, "temperature" = temperature, "buffer" = buffer_energy, "input" = last_input_watts, "output" = last_output_watts, "lossEnergy" = loss_joules, "parts" = parts, "limiting" = limiting_role, "configuration" = owner.material_configuration_revision, "liner" = owner.material_environment_liner_integrity, "shell" = owner.material_environment_exterior_integrity, "fatigue" = owner.material_environment_fatigue, "monitoring" = !!monitor_tool, "reading" = last_reading)
	if(istype(owner, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/emitter = owner
		data["emitter"] = list("output" = emitter.material_output_setting, "cadence" = emitter.material_cadence_setting, "stored" = emitter.material_stored_energy, "active" = emitter.active)
	return data

/datum/material_service/tgui_act(action, list/params, datum/tgui/ui)
	if(..())
		return TRUE
	if(QDELETED(owner) || !ui.user.Adjacent(owner) || ui.user.incapacitated())
		return TRUE
	if(action == "emitter_setting" && istype(owner, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/emitter = owner
		if(!emitter.allowed(ui.user) || emitter.locked)
			return TRUE
		var/value = text2num(params["value"])
		if(!isnum(value))
			return TRUE
		if(params["setting"] == "output")
			emitter.material_output_setting = clamp(value, 0.25, 3)
		else if(params["setting"] == "cadence")
			emitter.material_cadence_setting = clamp(value, 0.25, 3)
		emitter.material_service_changed()
		return TRUE
	return FALSE

/datum/material_service/proc/reset_observation()
	monitor_started = world.time
	monitor_last_time = world.time
	monitor_input = input_joules
	monitor_output = output_joules
	monitor_moles = delivered_moles
	monitor_last_input = input_joules
	monitor_last_output = output_joules
	monitor_last_moles = delivered_moles
	monitor_minimum_output = INFINITY
	monitor_minimum_flow = INFINITY
	monitor_minimum_pressure = INFINITY
	monitor_maximum_temperature = temperature
	monitor_stored_energy = owner.material_operating_reservoir()

/// Only physical observation records an interval. Opening/refreshing a UI does
/// not advance a test, and changing parts invalidates the in-progress interval.
/datum/material_service/proc/sample_observation()
	var/obj/item/multitool/tool = monitor_tool?.resolve()
	var/mob/living/user = monitor_user?.resolve()
	if(!tool || !istype(user) || user.incapacitated() || !user.Adjacent(owner) || !user.item_is_in_hands(tool))
		monitor_tool = null
		monitor_user = null
		return FALSE
	if(monitor_configuration != owner.material_configuration_revision)
		monitor_configuration = owner.material_configuration_revision
		reset_observation()
	monitor_maximum_temperature = max(monitor_maximum_temperature, temperature)
	var/datum/gas_mixture/destination = last_delivery_mixture?.resolve()
	if(destination)
		monitor_minimum_pressure = min(monitor_minimum_pressure, destination.return_pressure())
		monitor_maximum_temperature = max(monitor_maximum_temperature, destination.return_temperature())
	var/interval = (world.time - monitor_last_time) / 10
	if(interval < 10)
		return TRUE
	var/input = input_joules - monitor_last_input
	var/output = output_joules - monitor_last_output
	var/flow = delivered_moles - monitor_last_moles
	if(output <= 0 || input <= 0 || owner.material_environment_leaking || owner.material_environment_fatigue >= 100)
		reset_observation()
		last_input_watts = 0
		last_output_watts = 0
		return TRUE
	monitor_minimum_output = min(monitor_minimum_output, output / interval)
	monitor_minimum_flow = min(monitor_minimum_flow, flow / interval)
	monitor_minimum_pressure = min(monitor_minimum_pressure, last_delivery_pressure)
	monitor_maximum_temperature = max(monitor_maximum_temperature, temperature, last_delivery_temperature)
	last_input_watts = input / interval
	last_output_watts = output / interval
	monitor_last_input = input_joules
	monitor_last_output = output_joules
	monitor_last_moles = delivered_moles
	monitor_last_time = world.time
	var/duration = (world.time - monitor_started) / 10
	var/consumed = input_joules - monitor_input + monitor_stored_energy - owner.material_operating_reservoir()
	last_reading = list("name" = owner.name, "assembly" = owner.material_assembly_id, "configuration" = monitor_configuration, "started" = monitor_started, "ended" = world.time, "duration" = duration, "input_joules" = input_joules - monitor_input, "output_joules" = output_joules - monitor_output, "minimum_output_watts" = monitor_minimum_output, "minimum_flow_moles" = monitor_minimum_flow, "minimum_pressure_kpa" = monitor_minimum_pressure, "maximum_temperature_k" = monitor_maximum_temperature, "efficiency" = (output_joules - monitor_output) / max(consumed, 1), "kind" = owner.material_measurement_kind())
	tool.set_engineering_reading(last_reading)
	return TRUE

/obj/proc/material_measurement_kind()
	return "assembly"

/obj/proc/material_operating_reservoir()
	return 0

/obj/machinery/power/emitter/material_operating_reservoir()
	return material_stored_energy

/obj/item/cell/material_measurement_kind()
	return "power"

/obj/structure/cable/material_measurement_kind()
	return "power"

/obj/machinery/atmospherics/material_measurement_kind()
	return "gas"

/obj/machinery/portable_atmospherics/material_measurement_kind()
	return "gas"

/obj/machinery/power/emitter/material_measurement_kind()
	return "beam"

/obj/item/multitool/proc/set_engineering_reading(list/reading)
	if(engineering_evidence_id)
		SScontracts.release_evidence(engineering_evidence_id)
		engineering_evidence_id = null
	engineering_reading = reading.Copy()

/obj/item/multitool/Destroy()
	if(engineering_evidence_id)
		SScontracts?.release_evidence(engineering_evidence_id)
	engineering_evidence_id = null
	engineering_reading = null
	return ..()

/obj/machinery/photocopier/proc/print_engineering_reading(obj/item/multitool/tool, mob/user)
	if(!tool.engineering_reading || toner <= 0 || copying || stat & (NOPOWER|BROKEN))
		to_chat(user, span_warning("The copier needs toner and power, and the multitool needs a recorded reading."))
		return TRUE
	var/list/reading = tool.engineering_reading
	if(!tool.engineering_evidence_id)
		var/datum/money_account/account = medical_trial_account_for_mob(user)
		tool.engineering_evidence_id = SScontracts.register_evidence(CONTRACT_EVIDENCE_ENGINEERING, reading["assembly"], account?.account_number, tool, reading)
		SScontracts.retain_evidence(tool.engineering_evidence_id)
	var/obj/item/paper/report = new(get_turf(src))
	report.name = "engineering measurement — [reading["name"]]"
	report.info = "<h3>Engineering measurement</h3>"
	var/static/list/labels = list("name" = "Assembly", "assembly" = "Serial", "configuration" = "Configuration revision", "duration" = "Observed duration (seconds)", "input_joules" = "Input energy (J)", "output_joules" = "Delivered energy (J)", "minimum_output_watts" = "Minimum delivered power (W)", "minimum_flow_moles" = "Minimum gas transfer (mol/s)", "minimum_pressure_kpa" = "Minimum delivery pressure (kPa)", "maximum_temperature_k" = "Peak temperature (K)")
	for(var/key in labels)
		var/value = reading[key]
		if(isnull(value))
			continue
		if(isnum(value))
			value = round(value, 0.1)
		report.info += "<b>[labels[key]]:</b> [html_encode("[value]")]<br>"
	report.info += "<b>Measured efficiency:</b> [round(reading["efficiency"] * 100, 0.1)]%<br>"
	report.attach_contract_evidence(tool.engineering_evidence_id)
	report.update_icon()
	toner--
	use_power(active_power_usage)
	return TRUE
