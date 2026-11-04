/*
 * Text Mug
 */
/obj/item/reagent_containers/food/drinks/textmug
	name = "mug with text"
	desc = "A mug with something written on it."
	icon = 'icons/obj/drinks.dmi'
	icon_state = "textmug"
	volume = 30

CAPABILITIES(/obj/item/reagent_containers/food/drinks/textmug)
	configure(item_handling(center_x = 15, center_y = 13))
