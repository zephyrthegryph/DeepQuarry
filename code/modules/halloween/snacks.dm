/obj/item/reagent_containers/food/snacks/egg/rotten
	name = "rotten egg"
	desc = "A rotten egg. It stinks!"

DECLARE_REAGENTS(/obj/item/reagent_containers/food/snacks/egg/rotten, null, list(REAGENT_ID_SALMONELLA = 3))

/obj/item/storage/fancy/egg_box/rotten
	starts_with = list(/obj/item/reagent_containers/food/snacks/egg/rotten = 12)
