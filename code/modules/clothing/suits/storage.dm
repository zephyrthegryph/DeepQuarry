/obj/item/clothing/suit/storage
	name = DEVELOPER_WARNING_NAME
	var/obj/item/storage/internal/pockets // owned: the internal storage object that holds the pockets' contents

CAPABILITIES(/obj/item/clothing/suit/storage)
	owns_one(nameof(pockets), starts = /obj/item/storage/internal)
	op("suit_pockets_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Suit pockets hand"), then(PROC_REF(suit_pockets_hand)))
	op("suit_pockets_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Suit pockets item"), then(PROC_REF(suit_pockets_item)))

/obj/item/clothing/suit/storage/Initialize(mapload)
	. = ..()
	pockets.max_storage_space = ITEMSIZE_COST_SMALL * 2


/// Old attack_hand: the pockets get the touch first.
/obj/item/clothing/suit/storage/proc/suit_pockets_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (pockets.handle_attack_hand(user))
		return OP_DECLINE
	return OP_OK

/obj/item/clothing/suit/storage/MouseDrop(obj/over_object as obj)
	if (pockets.handle_mousedrop(usr, over_object))
		..(over_object)

/// Old attackby: the clothing's own item use (the old ..()), then the pockets.
/obj/item/clothing/suit/storage/proc/suit_pockets_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	clothing_accessory_item(A)
	pockets.attackby(W, user)
	return OP_PASS

//Jackets with buttons, used for labcoats, IA jackets, First Responder jackets, and brown jackets.
/obj/item/clothing/suit/storage/toggle
	name = DEVELOPER_WARNING_NAME
	flags_inv = HIDEHOLSTER
	var/open = 0	//0 is closed, 1 is open, -1 means it won't be able to toggle

CAPABILITIES(/obj/item/clothing/suit/storage/toggle)
	op("toggle_toggle_verb", menu(), label("Toggle Coat Buttons"), needs(carried()), then(PROC_REF(toggle_toggle_verb)))

/// Old verb "Toggle Coat Buttons".
/obj/item/clothing/suit/storage/toggle/proc/toggle_toggle_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return 0

	if(open == 1) //Will check whether icon state is currently set to the "open" or "closed" state and switch it around with a message to the user
		open = 0
		icon_state = initial(icon_state)
		flags_inv = HIDETIE|HIDEHOLSTER
		to_chat(user, "You button up the coat.")
	else if(open == 0)
		open = 1
		icon_state = "[icon_state]_open"
		flags_inv = HIDEHOLSTER
		to_chat(user, "You unbutton the coat.")
	else //in case some goofy admin switches icon states around without switching the icon_open or icon_closed
		to_chat(user, "You attempt to button-up the velcro on your [src], before promptly realising how silly you are.")
		return
	update_clothing_icon()	//so our overlays update

/obj/item/clothing/suit/storage/hooded/toggle
	name = DEVELOPER_WARNING_NAME
	flags_inv = HIDEHOLSTER
	var/open = 0	//0 is closed, 1 is open, -1 means it won't be able to toggle

TRACKED(/obj/item/clothing/suit/storage/hooded/toggle, open)

CAPABILITIES(/obj/item/clothing/suit/storage/hooded/toggle)
	op("hooded_toggle_toggle_verb", menu(), label("Toggle Coat Buttons"), needs(carried()), then(PROC_REF(hooded_toggle_toggle_verb)))

/// Old verb "Toggle Coat Buttons".
/obj/item/clothing/suit/storage/hooded/toggle/proc/hooded_toggle_toggle_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return 0

	if(open == 1) //Will check whether icon state is currently set to the "open" or "closed" state and switch it around with a message to the user
		set_open(0)
		flags_inv = HIDETIE|HIDEHOLSTER
		to_chat(user, "You button up the coat.")
	else if(open == 0)
		set_open(1)
		flags_inv = HIDEHOLSTER
		to_chat(user, "You unbutton the coat.")
	else //in case some goofy admin switches icon states around without switching the icon_open or icon_closed
		to_chat(user, "You attempt to button-up the velcro on your [src], before promptly realising how silly you are.")
		return
	if(istype(hood,/obj/item/clothing/head/hood/toggleable)) //checks if a hood (which you should use) is attached
		var/obj/item/clothing/head/hood/toggleable/T = hood
		T.set_open(open) //copy the jacket's open state to the hood
		T.update_clothing_icon()
	update_clothing_icon() //so our overlays update

/obj/item/clothing/suit/storage/hooded/toggle/look_parts(datum/look/look)
	..()
	look.state("[toggleicon][open ? "_open" : ""][hood_up ? "_t" : ""]")

//New Vest 4 pocket storage and badge toggles, until suit accessories are a thing.
/obj/item/clothing/suit/storage/vest/heavy/Initialize(mapload)
	. = ..()
	pockets.max_storage_space = ITEMSIZE_COST_SMALL * 4 // declared on /obj/item/clothing/suit/storage

/obj/item/clothing/suit/storage/vest
	var/icon_badge
	var/icon_nobadge

CAPABILITIES(/obj/item/clothing/suit/storage/vest)
	op("vest_toggle_verb", menu(), label("Adjust Badge"), needs(carried()), then(PROC_REF(vest_toggle_verb)))

/// Old verb "Adjust Badge".
/obj/item/clothing/suit/storage/vest/proc/vest_toggle_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return 0

	if(icon_state == icon_badge)
		icon_state = icon_nobadge
		to_chat(user, "You conceal \the [src]'s badge.")
	else if(icon_state == icon_nobadge)
		icon_state = icon_badge
		to_chat(user, "You reveal \the [src]'s badge.")
	else
		to_chat(user, "\The [src] does not have a badge.")
		return
	update_clothing_icon()

/obj/item/clothing/suit/storage/tailcoat
	name = "victorian tailcoat"
	desc = "A fancy victorian tailcoat."
	icon_state = "tailcoat"

/obj/item/clothing/suit/storage/victcoat
	name = "ladies black victorian coat"
	desc = "A fancy victorian coat."
	icon_state = "ladiesvictoriancoat"

/obj/item/clothing/suit/storage/victcoat/red
	name = "ladies red victorian coat"
	icon_state = "ladiesredvictoriancoat"
