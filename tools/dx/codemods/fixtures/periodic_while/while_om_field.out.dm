/obj/item/gizmo
	name = "gizmo"
	var/hum = 0

/obj/item/gizmo/var/on = FALSE
TRACKED(/obj/item/gizmo, on)
/obj/item/gizmo/var/jammed = FALSE
TRACKED(/obj/item/gizmo, jammed)
CAPABILITIES(/obj/item/gizmo)
	/// Hums while on and not jammed.
	every(1 SECOND, then(PROC_REF(gizmo_step)), when = cond_all(nameof(on), cond_not(nameof(jammed))))

/obj/item/gizmo/proc/gizmo_step(datum/act/timer/A)
	var/delta = 1 SECOND
	hum += delta

/obj/item/gizmo/big/gizmo_step(datum/act/timer/A)
	..()
	hum++
