// Overrides of an engine-declared output base (/atom/proc/draw(look) in code/engine/engine.dm).
/obj/machinery/lamp/draw(datum/look/look)
	..()
	look.state = lit ? "on" : "off"

/obj/machinery/lamp_bad
	name = "lamp_bad"

/obj/machinery/lamp_bad/draw(datum/look/look, extra)
	..()
