/obj/item/reagent_containers/food/snacks/tastybread
	name = "bread tube"
	desc = "Bread in a tube. Chewy...and surprisingly tasty."
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "tastybread"
	trash = VARIANT(/obj/item/trash, "tastybread")
	filling_color = "#A66829"
	nutriment_amt = 6
	nutriment_desc = list("bread" = 2, "sweetness" = 3)
	bitesize = 2

//So what if like yknow, you buy a bread tube and wow you actually get to test the new and improved producct.
/obj/item/reagent_containers/food/snacks/tastybread/sequel
	name = "bread tube 2"
	desc = "Bread in a tube. Chewy...and surprisingly tasty. Now with twice the bread to tube!"
	filling_color = "#75491c"
	nutriment_amt = 12
	nutriment_desc = list("bread" = 4, "sweetness" = 6)
	bitesize = 4

/obj/item/reagent_containers/food/snacks/tastybread/proc/roll_bread_sequel()
	if(prob(1))
		new /obj/item/reagent_containers/food/snacks/tastybread/sequel(src)
		spent(src)
		return

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tastybread)
	configure(atom_rules(price_tag = 2, description_fluff = "This is the product that brought Centauri Provisions into the limelight. A product of the earliest extrasolar colony of Heaven, the Bread Tube, while bland, contains all the nutrients a spacer needs to get through the day and is decidedly edible when compared to some of its competitors. Due to the high-fructose corn syrup content of NanoTrasen's own-brand bread tubes, many jurisdictions classify them as a confectionary."))
	configure(item_handling(center_x = 17, center_y = 16))
	setup(PROC_REF(roll_bread_sequel))
