/obj/item/gizmo
	name = "gizmo"
	icon_state = "gizmo"
	var/open = FALSE
	var/glow = 0

OM_FIELD(/obj/item/gizmo, lit, FALSE, CHANGE_EXPLICIT)

/obj/item/gizmo/proc/toggle()
	open = !open
	glow++
	update_icon()

/obj/item/gizmo/proc/reset(obj/item/gizmo/other)
	other.glow = 0
	other.open |= 1
	glow += 2

DECLARE_APPEARANCE_PROC(/obj/item/gizmo, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gizmo/appearance_overlays()
	. = list()
	icon_state = "gizmo[open]"
	if(glow)
		. += "gizmo-glow"
		color = "#fff"
	if(lit)
		. += list("lit-a", "lit-b")

/obj/item/loud
	name = "loud"

DECLARE_APPEARANCE_PROC(/obj/item/loud, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/loud/appearance_overlays()
	. = list()
	playsound(src, 'x.ogg', 10)
