/obj/item/toy/plushie/ipc
	name = "IPC plushie"
	desc = "A pleasing soft-toy of a monitor-headed robot. Toaster functionality included."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_ipc"
	pokephrase = "Ping!"
	squeeze_sound = SFX_MACHINES_PING

CAPABILITIES(/obj/item/toy/plushie/ipc)
	configure(atom_rules(bubble_icon = "synthetic"))
	op("ipc_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT + 1), then(PROC_REF(ipc_interaction_item)))

/// Old attackby.
/obj/item/toy/plushie/ipc/proc/ipc_interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/material/kitchen/utensil))
		to_chat(user, span_notice(" You insert the [I] into the toaster. "))
		fx_sparks(src, 5)
		user.electrocute_act(15,src,0.75)
	else
		return OP_DECLINE
	return OP_PASS

/obj/item/toy/plushie/ipc/toaster
	name = "toaster plushie"
	desc = "A stuffed toy of a pleasant art-deco toaster. It has a small tag on it reading 'Bricker Home Appliances! All rights reserved, copyright 2298.' It's a tad heavy on account of containing a heating coil. Want to make toast?"
	icon_state = "marketable_tost"
	pokephrase = "Ding!"
	squeeze_sound = SFX_MACHINES_DING

CAPABILITIES(/obj/item/toy/plushie/ipc/toaster)
	configure(atom_rules(bubble_icon = "machine"))
	configure(item_combat(attack_verbs = list("toasted", "burnt")))
