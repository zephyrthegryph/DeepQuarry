// A multitool observes an assembly while the operator remains beside it.
// Reports travel in the tool's memory and are printed by an existing copier.
/obj/item/multitool
	var/list/engineering_reading
	var/engineering_evidence_id

/datum/material_service
	/// The multitool observing the assembly, and who holds it (relation views).
	var/obj/item/multitool/monitor_tool
	var/mob/living/monitor_user
	var/monitor_last_input = 0
	var/monitor_last_output = 0
	var/monitor_last_moles = 0
	EXPIRY_DECLARE(monitor_last_time)
	var/monitor_configuration = -1
	var/maintenance_open = FALSE
	var/last_reading_id
	var/list/last_reading
	EXPIRY_DECLARE(monitor_started)
	var/monitor_input = 0
	var/monitor_output = 0
	var/monitor_moles = 0
	var/monitor_minimum_output = INFINITY
	var/monitor_minimum_flow = INFINITY
	var/monitor_maximum_temperature = 0
	var/monitor_minimum_pressure = INFINITY
	var/monitor_stored_energy = 0

/datum/material_service/proc/register_diagnostics()
	observe(owner(), /datum/act/tool_act, src, instead(then(PROC_REF(on_tool_act))))
	observe(owner(), /datum/act/attackby, src, instead(then(PROC_REF(replace_with_stock))))
	observe(owner(), /datum/notice/examine, src, then(PROC_REF(examine_service)))

/// Secondary multitool / screwdriver use on the owner.
/datum/material_service/proc/on_tool_act(datum/act/tool_act/use)
	SHOULD_NOT_SLEEP(TRUE)
	if(!use.secondary)
		return HOOK_DECLINE
	var/result = NONE
	switch(use.tool_quality)
		if(TOOL_MULTITOOL)
			result = inspect_with_tool(use.target, use.user, use.tool)
		if(TOOL_SCREWDRIVER)
			result = open_service_cover(use.target, use.user, use.tool)
	return result ? result : HOOK_DECLINE

/obj/proc/material_diagnostics_tool_act(mob/user, obj/item/tool)
	if(!has_functional_construction() || !tool?.has_tool_quality(TOOL_MULTITOOL))
		return NONE
	var/datum/material_service/service = material_service_event(MATERIAL_EVENT_MONITORING)
	if(!service)
		return NONE
	return service.inspect_with_tool(src, user, tool)

/datum/material_service/proc/unregister_diagnostics()
	unobserve(owner(), /datum/act/tool_act, src)
	unobserve(owner(), /datum/act/attackby, src)
	unobserve(owner(), /datum/notice/examine, src)
	rel_clear(src, nameof(monitor_tool))
	rel_clear(src, nameof(monitor_user))
	last_reading = null

/datum/material_service/proc/examine_service(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/examine/event = A
	var/list/text = event.texts
	text += span_notice("[summary()] Right-click with a multitool to measure operation; right-click with a screwdriver to open the service cover.")
	if(maintenance_open)
		text += span_notice("The service cover is open. Replacement material stock can be fitted to an individual component.")

/datum/material_service/proc/can_service(mob/user)
	if(!owner() || QDELETED(owner()) || !user || !user.Adjacent(owner()) || user.incapacitated())
		return FALSE
	if(ismachinery(owner()))
		var/obj/machinery/machine = owner()
		if(!machine.allowed(user))
			return FALSE
	if(istype(owner(), /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/emitter = owner()
		if(emitter.active)
			return FALSE
	return TRUE

/datum/material_service/proc/inspect_with_tool(datum/source, mob/user, obj/item/tool)
	SHOULD_NOT_SLEEP(TRUE)
	if(!user.Adjacent(owner()) || !tool?.has_tool_quality(TOOL_MULTITOOL))
		return ITEM_INTERACT_BLOCKING
	rel_set(src, nameof(monitor_tool), tool)
	rel_set(src, nameof(monitor_user), user)
	monitor_last_input = input_joules
	monitor_last_output = output_joules
	monitor_last_moles = delivered_moles
	EXPIRY_STAMP(src, monitor_last_time, CLOCK_WORLD)
	monitor_configuration = material_assembly_view(owner()).configuration_revision
	reset_observation()
	schedule(0)
	INVOKE_ASYNC(src, PROC_REF(tgui_interact), user) // ALLOW(scheduler): tgui_interact may block on asset/window setup
	return ITEM_INTERACT_SUCCESS

/datum/material_service/proc/open_service_cover(datum/source, mob/user, obj/item/tool)
	SHOULD_NOT_SLEEP(TRUE)
	if(!can_service(user))
		to_chat(user, span_warning("The assembly must be accessible and stopped before opening its service cover."))
		return ITEM_INTERACT_BLOCKING
	maintenance_open = !maintenance_open
	act_message(user, owner(), others = span_notice("%U% [maintenance_open ? "opens" : "closes"] [owner()]'s service cover."))
	return ITEM_INTERACT_SUCCESS

/datum/material_service/proc/replace_with_stock(datum/act/attackby/use)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/item/item = use.item
	var/mob/user = use.user
	if(!maintenance_open || !istype(item, /obj/item/stack/material))
		return HOOK_DECLINE
	INVOKE_ASYNC(src, PROC_REF(fit_stock), item, user) // ALLOW(scheduler): callee prompts (tgui_input_list)
	return TRUE

/datum/material_service/proc/fit_stock(obj/item/stack/material/stock, mob/user)
	if(!can_service(user) || !stock || stock.loc != user)
		return
	var/list/roles = list()
	for(var/role in owner().material_roles())
		roles += role
	var/role = rerun_ask(user, "k105", PROC_REF(fit_stock), args, /datum/prompt/choice, question = "Which component should be replaced?", title = "Service assembly", choices = roles)
	if(isnull(role))
		return
	if(!role || !can_service(user) || !maintenance_open || QDELETED(stock) || stock.loc != user || !(role in owner().material_roles()))
		return
	var/quantity = max(1, CEILING((owner().role_amount(role) || SHEET_MATERIAL_AMOUNT) / SHEET_MATERIAL_AMOUNT, 1))
	if(stock.get_amount() < quantity)
		to_chat(user, span_warning("This component requires [quantity] sheets."))
		return
	var/material_id = stock.get_material_name()
	task_start(/datum/task/timed/material_service_fit_stock, user, owner(), stock = stock, role = role, quantity = quantity, material_id = material_id)

/datum/task/timed/material_service_fit_stock
	duration = 2 SECONDS
	complete_proc = /datum/material_service/proc/fit_stock_done
	var/obj/item/stack/material/stock
	var/role
	var/quantity
	var/material_id

/datum/material_service/proc/fit_stock_done(datum/task/timed/material_service_fit_stock/task)
	var/obj/item/stack/material/stock = task.stock
	var/mob/user = task.actor
	var/role = task.role
	var/quantity = task.quantity
	var/material_id = task.material_id
	if(!can_service(user) || !maintenance_open || stock.loc != user || !stock.use(quantity))
		return
	advance()
	if(QDELETED(owner()))
		return
	owner().set_construction_material(role, material_id)
	var/datum/material_assembly/wear = material_assembly(owner())
	if(role == MATERIAL_ROLE_LINER)
		wear.liner_integrity = 100
	if(role == MATERIAL_ROLE_STRUCTURE)
		wear.exterior_integrity = 100
		wear.fatigue = 0
	if(wear.liner_integrity > 0 && wear.exterior_integrity > 0 && wear.fatigue < 100)
		wear.leaking = FALSE
		owner().material_environment_repaired()
	owner().material_service_changed()
	if(isitem(owner()))
		var/obj/item/item = owner()
		item.apply_material_role_effects(material_build_view(item).profile)
	if(istype(owner(), /obj/structure/cable))
		var/obj/structure/cable/cable = owner()
		cable.material_overlay?.invalidate_material_cache()
	act_message(user, owner(), others = span_notice("%U% fits a new [role] into [owner()]."))
	contents_changed()

/datum/material_service/tgui_host(mob/user)
	return owner()

CAPABILITIES(/datum/material_service)
	owns_many(nameof(gas_watches), /datum/native_watch/gas)
	interface("EngineeringAssembly")
	op("emitter_setting", ui_act("emitter_setting", arg("setting"), arg("value", num(0.25, 3))), then(PROC_REF(ui_act_emitter_setting)))

/datum/material_service/ui_title(mob/user)
	return "[owner().name] — diagnostics"

/// /datum/material_service's window data.
/datum/material_service/ui_data(datum/act/eval/A)
	var/list/parts = list()
	for(var/role in owner().material_roles())
		var/datum/material/material = owner().material_for_role(role)
		parts += list(list("role" = role, "material" = material.display_name || material.name, "meltingPoint" = material.melting_point, "corrosion" = material.corrosion_resistance, "purpose" = describe_part(role, material)))
	var/datum/material_assembly/wear = material_assembly_view(owner())
	var/list/data = list("status" = status, "temperature" = temperature(), "buffer" = buffer_energy(), "input" = last_input_watts, "output" = last_output_watts, "lossEnergy" = loss_joules, "parts" = parts, "limiting" = limiting_role, "configuration" = wear.configuration_revision, "liner" = wear.liner_integrity, "shell" = wear.exterior_integrity, "fatigue" = wear.fatigue, "monitoring" = !!monitor_tool, "reading" = last_reading)
	if(istype(owner(), /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/emitter = owner()
		data["emitter"] = list("output" = emitter.material_output_setting, "cadence" = emitter.material_cadence_setting, "stored" = emitter.material_stored_energy, "active" = emitter.active)
	return data

/datum/material_service/proc/describe_part(role, datum/material/material)
	switch(role)
		if(MATERIAL_ROLE_CONDUCTOR, MATERIAL_ROLE_CONTACTS, MATERIAL_ROLE_ELECTRODE)
			var/superconducting = material.critical_temperature ? "; superconducts below [round(material.critical_temperature)] K up to [round(material.critical_current_density)] current density" : ""
			return "Carries power: [round(material.conductivity)] conductivity[superconducting]."
		if(MATERIAL_ROLE_THERMAL)
			var/buffer = material.phase_change_capacity ? "; buffers [round(material.phase_change_capacity)] J near [round(material.phase_change_temperature)] K" : ""
			return "Controls operating heat: [round(material.specific_heat)] specific heat[buffer]."
		if(MATERIAL_ROLE_INSULATION, MATERIAL_ROLE_DIELECTRIC, MATERIAL_ROLE_JACKET)
			return "Limits heat or electrical leakage: [round(material.thermal_insulation)] insulation, [round(material.dielectric_strength)] dielectric strength."
		if(MATERIAL_ROLE_LINER)
			return "Touches the working fluid: [round(material.corrosion_resistance)] corrosion resistance."
		if(MATERIAL_ROLE_STRUCTURE, MATERIAL_ROLE_FRAME, MATERIAL_ROLE_BODY, MATERIAL_ROLE_BARREL)
			return "Carries mechanical load: [round(material.yield_strength)] yield strength, [round(material.fracture_toughness)] fracture toughness."
		if(MATERIAL_ROLE_OPTICAL, MATERIAL_ROLE_SENSOR, MATERIAL_ROLE_EMITTER)
			return "Shapes or measures output: [round(material.reflectivity * 100)]% reflectivity, [round(material.melting_point)] K thermal limit."
		if(MATERIAL_ROLE_ACTUATOR, MATERIAL_ROLE_BEARINGS, MATERIAL_ROLE_SPRING, MATERIAL_ROLE_FEED)
			return "Controls motion: [round(material.elasticity)] elasticity, [round(material.hardness)] hardness."
	return "Functional behavior follows this material's measured physical properties."

/datum/material_service/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(QDELETED(owner()) || !user.Adjacent(owner()) || user.incapacitated())
		return FALSE
	return TRUE

/datum/material_service/proc/ui_act_emitter_setting(datum/act/op/A, setting, value_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(setting) && !(setting in list("output", "cadence")))
		return FALSE
	var/obj/machinery/power/emitter/emitter = owner()
	if(!istype(emitter))
		return FALSE
	if(!emitter.allowed(user) || lock_locked(emitter))
		return TRUE
	var/value = value_arg
	if(!isnum(value))
		return TRUE
	if(setting == "output")
		emitter.material_output_setting = value
	else if(setting == "cadence")
		emitter.material_cadence_setting = value
	emitter.material_service_changed()
	return TRUE

/datum/material_service/proc/reset_observation()
	EXPIRY_STAMP(src, monitor_started, CLOCK_WORLD)
	EXPIRY_STAMP(src, monitor_last_time, CLOCK_WORLD)
	monitor_input = input_joules
	monitor_output = output_joules
	monitor_moles = delivered_moles
	monitor_last_input = input_joules
	monitor_last_output = output_joules
	monitor_last_moles = delivered_moles
	monitor_minimum_output = INFINITY
	monitor_minimum_flow = INFINITY
	monitor_minimum_pressure = INFINITY
	monitor_maximum_temperature = temperature()
	monitor_stored_energy = owner().material_operating_reservoir()

/// Only physical observation records an interval. Opening/refreshing a UI does
/// not advance a test, and changing parts invalidates the in-progress interval.
/datum/material_service/proc/sample_observation()
	var/obj/item/multitool/tool = monitor_tool
	var/mob/living/user = monitor_user
	if(!tool || !istype(user) || user.incapacitated() || !user.Adjacent(owner()) || !user.item_is_in_hands(tool))
		rel_clear(src, nameof(monitor_tool))
		rel_clear(src, nameof(monitor_user))
		return FALSE
	var/datum/material_assembly/wear = material_assembly_view(owner())
	if(monitor_configuration != wear.configuration_revision)
		monitor_configuration = wear.configuration_revision
		reset_observation()
	monitor_maximum_temperature = max(monitor_maximum_temperature, temperature())
	// The last delivery's destination, as recorded when the pump delivered (the mixture itself is
	// owned by its turf or network; the service keeps only the readings).
	if(last_delivery_pressure)
		monitor_minimum_pressure = min(monitor_minimum_pressure, last_delivery_pressure)
		monitor_maximum_temperature = max(monitor_maximum_temperature, last_delivery_temperature)
	var/interval = (world.time - monitor_last_time) / 10
	if(interval < 10)
		return TRUE
	var/input = input_joules - monitor_last_input
	var/output = output_joules - monitor_last_output
	var/flow = delivered_moles - monitor_last_moles
	if(output <= 0 || input <= 0 || wear.leaking || wear.fatigue >= 100)
		reset_observation()
		last_input_watts = 0
		last_output_watts = 0
		return TRUE
	monitor_minimum_output = min(monitor_minimum_output, output / interval)
	monitor_minimum_flow = min(monitor_minimum_flow, flow / interval)
	monitor_minimum_pressure = min(monitor_minimum_pressure, last_delivery_pressure)
	monitor_maximum_temperature = max(monitor_maximum_temperature, temperature(), last_delivery_temperature)
	last_input_watts = input / interval
	last_output_watts = output / interval
	monitor_last_input = input_joules
	monitor_last_output = output_joules
	monitor_last_moles = delivered_moles
	EXPIRY_STAMP(src, monitor_last_time, CLOCK_WORLD)
	var/duration = (world.time - monitor_started) / 10
	var/consumed = input_joules - monitor_input + monitor_stored_energy - owner().material_operating_reservoir()
	var/datum/money_account/observer_account = contract_account_for_mob(user)
	last_reading = list("name" = owner().name, "assembly" = wear.assembly_id, "configuration" = monitor_configuration, "started" = monitor_started, "ended" = EXPIRY_AT(null, CLOCK_WORLD, 0), "duration" = duration, "input_joules" = input_joules - monitor_input, "output_joules" = output_joules - monitor_output, "minimum_output_watts" = monitor_minimum_output, "minimum_flow_moles" = monitor_minimum_flow, "minimum_pressure_kpa" = monitor_minimum_pressure, "maximum_temperature_k" = monitor_maximum_temperature, "efficiency" = (output_joules - monitor_output) / max(consumed, 1), "kind" = owner().material_measurement_kind(), "observer_account" = observer_account?.account_number, "observer_name" = user.real_name)
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

// releases its engineering evidence id.
/obj/item/multitool/on_destroy(force)
	if(engineering_evidence_id)
		SScontracts?.release_evidence(engineering_evidence_id)
	..()

/obj/machinery/photocopier/proc/print_engineering_reading(obj/item/multitool/tool, mob/user)
	if(!tool.engineering_reading || toner <= 0 || copying || !operable())
		to_chat(user, span_warning("The copier needs toner and power, and the multitool needs a recorded reading."))
		return TRUE
	var/list/reading = tool.engineering_reading
	if(!tool.engineering_evidence_id)
		tool.engineering_evidence_id = SScontracts.register_evidence(CONTRACT_EVIDENCE_ENGINEERING, reading["assembly"], reading["observer_account"], tool, reading)
		SScontracts.retain_evidence(tool.engineering_evidence_id)
	var/obj/item/paper/report = new(get_turf(src))
	report.name = "engineering measurement — [reading["name"]]"
	report.info = "<h3>Engineering measurement</h3>"
	report.info += "<b>Observer:</b> [html_encode("[reading["observer_name"] || "Unidentified operator"]")]<br>"
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
	toner--
	use_power(active_power_usage)
	return TRUE
