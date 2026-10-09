/obj/item/pizzavoucher
	name = "free pizza voucher"
	desc = "A pocket-sized plastic slip with a button in the middle. The writing on it seems to have faded."
	icon = 'icons/obj/items.dmi'
	icon_state = "pizza_voucher"
	var/spent = FALSE
	var/special_delivery = FALSE
	w_class = ITEMSIZE_SMALL

/obj/item/pizzavoucher/Initialize(mapload)
	. = ..()
	var/list/descstrings = list("24/7 PIZZA PIE HEAVEN",
	"WE ALWAYS DELIVER!",
	"24-HOUR PIZZA PIE POWER!",
	"TOMATO SAUCE, CHEESE, WE'VE BOTH OF THESE!",
	"COOKED WITH LOVE INSIDE A BIG OVEN!",
	"WHEN YOU NEED A SLICE OF JOY IN YOUR LIFE!",
	"WHEN YOU NEED A DISK OF OVEN BAKED BLISS!",
	"EVERY TIME YOU DREAM OF CIRCULAR CUISINE!",
	"WE ALWAYS DELIVER! WE ALWAYS DELIVER! WE ALWAYS DELIVER!")
	desc = "A pocket-sized plastic slip with a button in the middle. \"[pick(descstrings)]\" is written on the back."

CAPABILITIES(/obj/item/pizzavoucher)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/// Old attack_self.
/obj/item/pizzavoucher/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!spent)
		act_message(user, src, others = span_notice("%U% presses a button on %T%!"))
		desc = desc + " This one seems to be used-up."
		spent = TRUE
		act_message(user, null, MSG_SELF(span_notice("A small bluespace rift opens just above your head and spits out a pizza box!")), \
			MSG_OTHERS(span_notice("A small bluespace rift opens just above %U%'s head and spits out a pizza box!")), \
			MSG_BLIND(span_notice("You hear a fwoosh followed by a thump.")))
		if(special_delivery)
			GLOB.command_announcement.Announce("SPECIAL DELIVERY PIZZA ORDER #[rand(1000,9999)]-[rand(100,999)] HAS BEEN RECEIVED. SHIPMENT DISPATCHED VIA EXTRA-POWERFUL BALLISTIC LAUNCHERS FOR IMMEDIATE DELIVERY! THANK YOU AND ENJOY YOUR PIZZA!", "WE ALWAYS DELIVER!")
			new /obj/effect/falling_effect/pizza_delivery/special(user.loc)
		else
			new /obj/effect/falling_effect/pizza_delivery(user.loc)
	else
		to_chat(user, span_warning("The [src] is spent!"))
	return TRUE

/obj/item/pizzavoucher/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(spent)
		to_chat(user, span_warning("The [src] is spent!"))
		return OP_DECLINE
	if(!special_delivery)
		to_chat(user, span_warning("You activate the special delivery protocol on the [src]!"))
		special_delivery = TRUE
		return OP_OK
	else
		to_chat(user, span_warning("The [src] is already in special delivery mode!"))
	return OP_DECLINE

/obj/effect/falling_effect/pizza_delivery
	name = "PIZZA PIE POWER!"
	crushing = FALSE
	falling_type = /loot/pizza_delivery

CAPABILITIES(/loot/pizza_delivery)
	loot(
		table = list(
			/obj/item/pizzabox/meat,
			/obj/item/pizzabox/margherita,
			/obj/item/pizzabox/vegetable,
			/obj/item/pizzabox/mushroom,
			/obj/item/pizzabox/pineapple))

/obj/effect/falling_effect/pizza_delivery/special
	crushing = TRUE
