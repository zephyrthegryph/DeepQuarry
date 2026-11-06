
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

/// A node draws no colour of its own: the blob body under it is tinted by its overmind, and the node overlay sits on top.
/obj/structure/blob/node/look_parts(datum/look/look)
	look.overlay(look_appearance('icons/mob/blob.dmi', "blob", color = look_tint))
	if(look_title)
		look.identity(name = "[look_title] [base_name]")
	look.overlay("blob_node_overlay")

/obj/structure/blob/node/proc/node_step(datum/act/timer/A)
	if(overmind) // This check is so that if the core is killed, the nodes stop.
		pulse_area(overmind, 10, BLOB_NODE_PULSE_RANGE, BLOB_NODE_EXPAND_RANGE)

		overmind.blob_type.on_node_process(src)
