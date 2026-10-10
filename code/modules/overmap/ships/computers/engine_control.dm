//Engine control and monitoring console

/obj/machinery/computer/ship/engines
	name = "engine control console"
	icon_keyboard = "tech_key"
	icon_screen = "engines"
	circuit = /obj/item/circuitboard/engine

// fancy sprite
/obj/machinery/computer/ship/engines/adv
	icon_keyboard = null
	icon_state = "adv_engines"
	icon_screen = "adv_engines_screen"
	light_color = "#05A6A8"

// The engines window: one op per button; the two thrust limits are asked in the window's op (asks()), the answer applied by its handler.
CAPABILITIES(/obj/machinery/computer/ship/engines)
	interface("OvermapEngines")
	without("ui_open")
	op("global_toggle", ui_act("global_toggle"), then(PROC_REF(ui_act_global_toggle)))
	op("set_global_limit", ui_act("set_global_limit"), asks(/datum/prompt/number/ship_console_global_limit, fields = list("default" = computed(PROC_REF(global_limit_default))), step = "limit"),
		then(PROC_REF(ui_act_set_global_limit)))
	op("global_limit", ui_act("global_limit", arg("global_limit", num())), then(PROC_REF(ui_act_global_limit)))
	op("set_limit", ui_act("set_limit", arg("engine", schema_ref(/datum/ship_engine))), needs(req(PROC_REF(engine_named), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = "Input new thrust limit (0..100)", "title" = "Thrust limit", "default" = computed(PROC_REF(engine_limit_default)), "max_value" = 100, "timeout" = 0), step = "limit"),
		then(PROC_REF(ui_act_set_limit)))
	op("limit", ui_act("limit", arg("engine", schema_ref(/datum/ship_engine)), arg("limit", num())), needs(req(PROC_REF(engine_named), silent = TRUE)), then(PROC_REF(ui_act_limit)))
	op("toggle_engine", ui_act("toggle_engine", arg("engine", schema_ref(/datum/ship_engine))), needs(req(PROC_REF(engine_named), silent = TRUE)), then(PROC_REF(ui_act_toggle_engine)))

/// A button that names an engine names one.
/obj/machinery/computer/ship/engines/proc/engine_named(datum/act/op/A)
	return (!isnull(A.args["engine"])) ? null : /datum/msg/req_failed

/obj/machinery/computer/ship/engines/proc/global_limit_default(datum/act/op/A)
	return linked()?.thrust_limit * 100

/obj/machinery/computer/ship/engines/proc/engine_limit_default(datum/act/op/A)
	var/datum/ship_engine/E = A.args["engine"]
	return E?.get_thrust_limit()

/// The keyboard under the operator's fingers (a silicon types nothing).
/obj/machinery/computer/ship/proc/terminal_typed(mob/user)
	if(!issilicon(user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/obj/machinery/computer/ship/engines/ui_prepare(mob/user, datum/tgui/ui)
	if(!linked())
		display_reconnect_dialog(user, "ship control systems")
		return FALSE

	return TRUE

/obj/machinery/computer/ship/engines/ui_title(mob/user)
	return "[linked().name] Engines Control"

/// The window data.
/obj/machinery/computer/ship/engines/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["global_state"] = linked().engines_state
	data["global_limit"] = round(linked().thrust_limit*100)
	var/total_thrust = 0

	var/list/enginfo = list()
	for(var/datum/ship_engine/E in linked().engines)
		var/list/rdata = list()
		rdata["eng_type"] = E.name
		rdata["eng_on"] = E.is_on()
		rdata["eng_thrust"] = E.get_thrust()
		rdata["eng_thrust_limiter"] = round(E.get_thrust_limit()*100)
		var/list/status = E.get_status()
		if(!islist(status))
			log_runtime(EXCEPTION("Warning, ship [E.name] (\ref[E]) for [linked().name] returned a non-list status!"))
			status = list("Error")
		rdata["eng_status"] = status
		rdata["eng_reference"] = "\ref[E]"
		total_thrust += E.get_thrust()
		enginfo.Add(list(rdata))

	data["engines_info"] = enginfo
	data["total_thrust"] = total_thrust
	return data

/obj/machinery/computer/ship/engines/proc/ui_act_global_toggle(datum/act/op/A)
	linked().engines_state = !linked().engines_state
	for(var/datum/ship_engine/E in linked().engines)
		if(linked().engines_state == !E.is_on())
			E.toggle()
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/engines/proc/ui_act_set_global_limit(datum/act/op/A)
	var/newlim = A.step_value("limit")
	linked().thrust_limit = clamp(newlim/100, 0, 1)
	for(var/datum/ship_engine/E in linked().engines)
		E.set_thrust_limit(linked().thrust_limit)
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/engines/proc/ui_act_global_limit(datum/act/op/A, global_limit)
	linked().thrust_limit = clamp(linked().thrust_limit + global_limit, 0, 1)
	for(var/datum/ship_engine/E in linked().engines)
		E.set_thrust_limit(linked().thrust_limit)
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/engines/proc/ui_act_set_limit(datum/act/op/A, datum/ship_engine/engine)
	engine.set_thrust_limit(clamp(A.step_value("limit")/100, 0, 1))
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/engines/proc/ui_act_limit(datum/act/op/A, datum/ship_engine/engine, limit)
	engine.set_thrust_limit(clamp(engine.get_thrust_limit() + limit, 0, 1))
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/engines/proc/ui_act_toggle_engine(datum/act/op/A, datum/ship_engine/engine)
	engine.toggle()
	terminal_typed(A.actor)
	return TRUE

/datum/prompt/number/ship_console_global_limit
	question = "Input new thrust limit (0..100%)"
	title = "Thrust limit"
	timeout = 0

/datum/prompt/number/ship_console_global_limit/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default || 0, 100, 0, timeout, FALSE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
