/* Warm Mugs!
 *
 * Contains:
 *		Britcup
 *		Text Mug
 *		Coffee Mugs
 *		Tall Mugs
 */

/*
 * Britcup
 */
/obj/item/reagent_containers/food/drinks/britcup
	name = "cup"
	desc = "A cup with the British flag emblazoned on it."
	icon_state = "britcup"
	volume = 30

CAPABILITIES(/obj/item/reagent_containers/food/drinks/britcup)
	configure(item_handling(center_x = 15, center_y = 13))
