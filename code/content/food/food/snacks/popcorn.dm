/obj/item/reagent_containers/food/snacks/popcorn
	name = "Popcorn"
	desc = "Now let's find some cinema."
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "popcorn"
	trash = /obj/item/trash/popcorn
	var/unpopped = 0
	filling_color = "#FFFAD4"
	nutriment_amt = 2
	nutriment_desc = list("popcorn" = 3)
	bitesize = 0.1 //This snack is supposed to be eaten for a long time.

CAPABILITIES(/obj/item/reagent_containers/food/snacks/popcorn)
	configure(atom_rules(price_tag = 3))
	configure(item_handling(center_x = 16, center_y = 8))
	rolls(nameof(unpopped), range_of(1, 10))

/obj/item/reagent_containers/food/snacks/popcorn/On_Consume(mob/living/M)
	if(prob(unpopped))	//lol ...what's the point?
		to_chat(M, span_red("You bite down on an un-popped kernel!"))
		set_unpopped(max(0, unpopped-1))
	. = ..()
