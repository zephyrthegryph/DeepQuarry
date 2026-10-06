
/obj/structure/blob/node
	name = "blob node"
	base_name = "node"
	icon_state = "blank_blob"
	desc = "A large, pulsating yellow mass."
	max_integrity = 50
	health_regen = 3
	point_return = 50

REGISTRY_MEMBERSHIP(/obj/structure/blob/node, REGISTRY_BLOB_NODES)

CAPABILITIES(/obj/structure/blob/node)
	every(2 SECONDS, then(PROC_REF(node_step)))

/obj/structure/blob/node/Initialize(mapload, new_overmind)
	. = ..()
	update_icon()

DECLARE_APPEARANCE_PROC(/obj/structure/blob/node, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/blob/node/appearance_overlays()
	. = list()
	color = null
	var/mutable_appearance/blob_overlay = mutable_appearance('icons/mob/blob.dmi', "blob")
	if(overmind)
		name = "[overmind.blob_type.name] [base_name]"
		blob_overlay.color = overmind.blob_type.color
	. += blob_overlay
	. += "blob_node_overlay"

/obj/structure/blob/node/proc/node_step(datum/act/timer/A)
	if(overmind) // This check is so that if the core is killed, the nodes stop.
		pulse_area(overmind, 10, BLOB_NODE_PULSE_RANGE, BLOB_NODE_EXPAND_RANGE)

		overmind.blob_type.on_node_process(src)
