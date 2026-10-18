/obj/item/clothing/suit/technomancer
	name = "chrome manipulation suit"
	desc = "It's a very shiny and somewhat protective suit, built to help carry cores on the user's back."
	icon_state = "technomancer"
	armor_spec = "melee=50;bullet=20;laser=30;energy=30;bomb=10;rad=40"

CAPABILITIES(/obj/item/clothing/suit/technomancer)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_ALL_TANKS), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = CHEST|ARMS|LEGS|FEET|HANDS))
	configure(item_protection(siemens = 0.75))


/obj/item/clothing/under/technomancer
	name = "initiate's jumpsuit"
	desc = "It's a blue colored jumpsuit.  There appears to be light-weight armor padding underneath, providing some protection.  \
	There is also a healthy amount of insulation underneath."
	icon_state = "initiate"
	armor_spec = "melee=10;bullet=5;laser=5"

CAPABILITIES(/obj/item/clothing/under/technomancer)
	configure(item_protection(siemens = 0.3))

/obj/item/clothing/under/technomancer/apprentice
	name = "apprentice's jumpsuit"
	desc = "It's a blue colored jumpsuit with some silver markings.  There appears to be light-weight armor padding \
	underneath, providing some protection.  There is also a healthy amount of insulation underneath."
	icon_state = "apprentice"

/obj/item/clothing/under/technomancer/master
	name = "master's jumpsuit"
	desc = "It's a blue colored jumpsuit with some gold markings.  There appears to be light-weight armor padding \
	underneath, providing some protection.  There is also a healthy amount of insulation underneath."
	icon_state = "technomancer"

/obj/item/clothing/head/technomancer
	name = "initiate's hat"
	desc = "It's a somewhat silly looking blue pointed hat."
	icon_state = "initiate"
	armor_spec = "melee=10;bullet=5;laser=5"

CAPABILITIES(/obj/item/clothing/head/technomancer)
	configure(item_protection(siemens = 0.3))

/obj/item/clothing/head/technomancer/apprentice
	name = "apprentice's hat"
	desc = "It's a somewhat silly looking blue pointed hat.  This one has a silver colored metalic feather strapped to it."
	icon_state = "apprentice"

/obj/item/clothing/head/technomancer/master
	name = "master's hat"
	desc = "It's a somewhat silly looking blue pointed hat.  This one has a gold colored metalic feather strapped to it."
	icon_state = "technomancer"
