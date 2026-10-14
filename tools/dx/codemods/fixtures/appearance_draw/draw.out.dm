/obj/item/gizmo
	name = "gizmo"
	icon_state = "gizmo"
	var/open = FALSE
	var/glow = 0
TRACKED(/obj/item/gizmo, glow)
TRACKED(/obj/item/gizmo, open)

/obj/item/gizmo/var/lit = FALSE
TRACKED(/obj/item/gizmo, lit)

/obj/item/gizmo/proc/toggle()
	set_open(!open)
	set_glow(glow + 1)
	update_icon()

/obj/item/gizmo/proc/reset(obj/item/gizmo/other)
	other.set_glow(0)
	other.set_open(other.open | 1)
	set_glow(glow + 2)

/obj/item/gizmo/draw(datum/look/look)
	..()
	look.state("gizmo[open]")
	if(glow)
		look.overlay("gizmo-glow")
		look.color = "#fff"
	if(lit)
		look.overlay("lit-a")
		look.overlay("lit-b")

/obj/item/loud
	name = "loud"

DECLARE_APPEARANCE_PROC(/obj/item/loud, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/loud/appearance_overlays()
	. = list()
	playsound(src, 'x.ogg', 10)
