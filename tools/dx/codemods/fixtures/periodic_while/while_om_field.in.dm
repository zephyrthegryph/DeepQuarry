/obj/item/gizmo
	name = "gizmo"
	var/hum = 0

OM_FIELD(/obj/item/gizmo, on, FALSE, CHANGE_EXPLICIT)
OM_FIELD(/obj/item/gizmo, jammed, FALSE, CHANGE_EXPLICIT)
/// Hums while on and not jammed.
DECLARE_PERIODIC_WHILE_ALL(/obj/item/gizmo, PERIODIC_SECOND, list("on", "!jammed"))

/obj/item/gizmo/periodic_step(delta)
	hum += delta

/obj/item/gizmo/big/periodic_step(delta)
	..()
	hum++
