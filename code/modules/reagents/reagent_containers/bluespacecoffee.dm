/obj/item/reagent_containers/food/drinks/bluespace_coffee
	name = "bluespace coffee"
	desc = "Dreamt up in a strange feverish dream, this coffee cup seems to have been heavily modified with a variety of unlikely parts and wires, and never seems to run out of coffee. Truly the differance between madmen and genius is success."
	icon = 'icons/obj/coffee.dmi'
	icon_state = "bluespace_coffee"
	center_of_mass_x = 15
	center_of_mass_y = 10
	volume = 50
	max_transfer_amount = 50

CAPABILITIES(/obj/item/reagent_containers/food/drinks/bluespace_coffee)
	configure(reagents(add = list(REAGENT_ID_COFFEE = 50)))

// Infinite Coffee: what a sip took is back a moment after it.
/obj/item/reagent_containers/food/drinks/bluespace_coffee/On_Consume(mob/living/eater, mob/feeder, changed = FALSE)
	. = ..()
	reagents.add_reagent(REAGENT_ID_COFFEE, 50)
