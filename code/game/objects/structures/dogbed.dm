/obj/structure/dogbed
	name = "dog bed"
	desc = "A bed made especially for dogs, or other similarly sized pets."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "dogbed"
	can_buckle = TRUE

CAPABILITIES(/obj/structure/dogbed)
	configure(seat_policy(direction = SOUTH, lying = 1))
