// Note that this is contained inside an actual implant subtype.
// See code/game/objects/items/weapons/implants/implantcircuits.dm for where this gets held.

/obj/item/electronic_assembly/implant
	name = "electronic implant"
	icon_state = "setup_implant"
	desc = "It's a case, for building very tiny electronics with."
	w_class = ITEMSIZE_TINY
	max_components = IC_COMPONENTS_BASE / 2
	max_complexity = IC_COMPLEXITY_BASE / 2
	var/tmp/implant_handle

/obj/item/electronic_assembly/implant/tgui_host()
	return implant().tgui_host()

DECLARE_APPEARANCE_PROC(/obj/item/electronic_assembly/implant, PROC_REF(appearance_overlays), list())
/obj/item/electronic_assembly/implant/appearance_overlays()
	. = list()
	. += ..()
	implant().icon_state = icon_state

/// LC-refs: the implant this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/electronic_assembly/implant/proc/implant() as /obj/item/implant/integrated_circuit
	return om_resolve(implant_handle)
