/obj/item/clothing/mask/balaclava
	name = "balaclava"
	desc = "LOADSAMONEY"
	icon_state = "balaclava"
	item_state_slots = list(slot_r_hand_str = "bandblack", slot_l_hand_str = "bandblack")
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/clothing/mask/balaclava)
	configure(item_worn(hides = HIDEFACE|BLOCKHAIR, covers = FACE|HEAD))

/obj/item/clothing/mask/balaclava/tactical
	name = "green balaclava"
	desc = "Designed to both hide identities and keep your face comfy and warm."
	icon_state = "swatclava"
	item_state_slots = list(slot_r_hand_str = "bandgreen", slot_l_hand_str = "bandgreen")
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/clothing/mask/balaclava/tactical)
	configure(item_worn(hides = HIDEFACE|BLOCKHAIR))

/obj/item/clothing/mask/luchador
	name = "Luchador Mask"
	desc = "Worn by robust fighters, flying high to defeat their foes!"
	icon_state = "luchag"
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/clothing/mask/luchador)
	configure(item_worn(hides = HIDEFACE|BLOCKHAIR, covers = HEAD|FACE))
	configure(item_protection(siemens = 3.0))

/obj/item/clothing/mask/luchador/tecnicos
	name = "Tecnicos Mask"
	desc = "Worn by robust fighters who uphold justice and fight honorably."
	icon_state = "luchador"

/obj/item/clothing/mask/luchador/rudos
	name = "Rudos Mask"
	desc = "Worn by robust fighters who are willing to do anything to win."
	icon_state = "luchar"

/obj/item/clothing/mask/luchador/colorable
	name = "Wrestling Mask"
	desc = "A mask that covers the top half of the head, worn by robust wrestlers."
	icon_state = "wrestler"
