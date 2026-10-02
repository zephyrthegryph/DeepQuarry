// The fixture of `analyze gen ui_types`: a window declared with interface() and ui_shape(), typed from tracked schemas.

/obj/ui_pump
	var/target_pressure = 101
	var/mode = "off"
	var/on = FALSE

TRACKED_SCHEMA(/obj/ui_pump, target_pressure, num(0, MAX_PUMP_PRESSURE, step = 1), default = 101)
TRACKED_SCHEMA(/obj/ui_pump, mode, enum(list("off", "on", "syphon")))
TRACKED_SCHEMA(/obj/ui_pump, on, bool())

CAPABILITIES(/obj/ui_pump, \
	interface("PumpDemo", title = "Pump"), \
	ui_shape(target_pressure, mode, on), \
	op("set_pressure", ui_act(arg("pressure", from = nameof(target_pressure))), then(PROC_REF(set_pressure))), \
	op("set_mode", ui_act("mode", arg("mode", enum(list("off", "on", "syphon")))), then(PROC_REF(set_mode))), \
	op("power", ui_act(), toggles(nameof(on))))
