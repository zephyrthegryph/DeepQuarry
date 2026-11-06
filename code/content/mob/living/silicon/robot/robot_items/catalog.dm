//This is used to unlock other borg covers.
/obj/item/card/robot //This is not a child of id cards, as to avoid dumb typechecks on computers.
	name = "access code transmission device"
	icon_state = "id-robot"
	desc = "A circuit grafted onto the bottom of an ID card.  It is used to transmit access codes into other robot chassis, \
	allowing you to lock and unlock other robots' panels."

	var/dummy_card = null
	var/dummy_card_type = /obj/item/card/id/science/roboticist/dummy_cyborg

CAPABILITIES(/obj/item/card/robot)
	owns_one(nameof(dummy_card), starts = nameof(dummy_card_type))

/obj/item/card/robot/GetID()
	return dummy_card

/obj/item/card/robot/syndi
	dummy_card_type = /obj/item/card/id/syndicate/dummy_cyborg

/obj/item/card/id/science/roboticist/dummy_cyborg
	access = list(ACCESS_ROBOTICS)

/obj/item/card/id/syndicate/dummy_cyborg/starting_access()
	return ..() | ACCESS_ROBOTICS

/obj/item/borg/combat/mobility
	name = "mobility module"
	desc = "By retracting limbs and tucking in its head, a combat android can roll at high speeds."
	icon = 'icons/obj/decals.dmi'
	icon_state = "shock"
