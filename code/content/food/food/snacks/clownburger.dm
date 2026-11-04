/obj/item/reagent_containers/food/snacks/clownburger
	name = JOB_CLOWN + " Burger"
	desc = "This tastes funny..."
	icon_state = "clownburger"
	filling_color = "#FF00FF"
	nutriment_amt = 6
	nutriment_desc = list("bun" = 2, "clown shoe" = 3)
	bitesize = 2

// begin - honkwork infection
CAPABILITIES(/obj/item/reagent_containers/food/snacks/clownburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 17, center_y = 12))
	configure(reagents(add = list("protein" = 2)))

/obj/item/reagent_containers/food/snacks/clownburger/On_Consume(mob/living/user)
	if(user && ishuman(user) && prob(3))
		var/mob/living/carbon/human/H = user
		H.malignant_organ_spawn( /obj/item/organ/internal/malignant/parasite/honker )
	. = ..()
