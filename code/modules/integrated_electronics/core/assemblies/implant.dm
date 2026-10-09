// Note that this is contained inside an actual implant subtype.
// See code/game/objects/items/weapons/implants/implantcircuits.dm for where this gets held.

/obj/item/electronic_assembly/implant
	name = "electronic implant"
	icon_state = "setup_implant"
	desc = "It's a case, for building very tiny electronics with."
	w_class = ITEMSIZE_TINY
	max_components = IC_COMPONENTS_BASE / 2
	max_complexity = IC_COMPLEXITY_BASE / 2
	var/tmp/obj/item/implant/integrated_circuit/implant

/obj/item/electronic_assembly/implant/tgui_host()
	return implant().tgui_host()

/obj/item/electronic_assembly/implant/draw(datum/look/look)
	..()
	look.effect(PROC_REF(sync_implant_state), look.state_so_far(src))

/// The implant shows the assembly's sprite state.
/obj/item/electronic_assembly/implant/proc/sync_implant_state(shown)
	if(implant())
		implant().icon_state = shown

/// The implant this refers to (a relation view: null once that is deleted).
/obj/item/electronic_assembly/implant/proc/implant() as /obj/item/implant/integrated_circuit
	return implant
