/obj/item/kinetic_crusher/glaive
	name = "kinetic glaive"
	icon_state = "crusher-glaive"
	detonation_damage = 20 // 40
	backstab_bonus = 30 // 60
	w_class = ITEMSIZE_NORMAL
	requires_wield = FALSE

/obj/item/pickaxe/anamolous
	name = "strange pickaxe"
	icon_state = "ppickaxe"
	item_state = "ppickaxe"
	digspeed = 2
	desc = "This oddly lightweight pickaxe seems rather sturdy."

CAPABILITIES(/obj/item/pickaxe/anamolous)
	configure(item_thrown(force = 25.0))

/obj/item/kinetic_crusher
	requires_wield = FALSE
