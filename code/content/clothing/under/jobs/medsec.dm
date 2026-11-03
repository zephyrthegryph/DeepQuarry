/obj/item/clothing/under/rank/brigphys
	name = "brig physician's jumpsuit"
	desc = "It's made of a special fiber that provides minor protection against biohazards. It has a cross on the chest denoting that the wearer is trained medical personnel."
	icon_state = "brigphys"
	item_state_slots = list(slot_r_hand_str = "white", slot_l_hand_str = "white")
	rolled_sleeves = 0

CAPABILITIES(/obj/item/clothing/under/rank/brigphys)
	configure(atom_rules(armor_spec = "bio=10"))
	configure(item_protection(permeability = 0.50))

/obj/item/clothing/under/rank/brigphys/jeans
	icon_state = "brigphysj"
