/obj/item/reagent_containers/food/snacks/mysterysoup
	name = "Mystery soup"
	desc = "The mystery is, why aren't you eating it?"
	icon_state = "mysterysoup"
	trash = /obj/item/trash/snack_bowl
	filling_color = "#F082FF"
	nutriment_amt = 1
	nutriment_desc = list("backwash" = 1)
	bitesize = 5
	eating_sound = SFX_ITEMS_DRINK

/obj/item/reagent_containers/food/snacks/mysterysoup
	/// Which of the ten mystery recipes it rolled (rolls()).
	var/mystery_recipe = 0

CAPABILITIES(/obj/item/reagent_containers/food/snacks/mysterysoup)
	configure(atom_rules(price_tag = 3))
	configure(item_handling(center_x = 16, center_y = 6))
	rolls(nameof(mystery_recipe), range_of(1, 10))
	configure(reagents(contents_from = PROC_REF(mystery_contents)))

TYPE_TABLE_DECLARE(/obj/item/reagent_containers/food/snacks/mysterysoup, mystery_soup_recipes, list(
	list(REAGENT_ID_NUTRIMENT = 6, REAGENT_ID_CAPSAICIN = 3, REAGENT_ID_TOMATOJUICE = 2),
	list(REAGENT_ID_NUTRIMENT = 6, REAGENT_ID_FROSTOIL = 3, REAGENT_ID_TOMATOJUICE = 2),
	list(REAGENT_ID_NUTRIMENT = 5, REAGENT_ID_WATER = 5, REAGENT_ID_TRICORDRAZINE = 5),
	list(REAGENT_ID_NUTRIMENT = 5, REAGENT_ID_WATER = 10),
	list(REAGENT_ID_NUTRIMENT = 2, REAGENT_ID_BANANA = 10),
	list(REAGENT_ID_NUTRIMENT = 6, REAGENT_ID_BLOOD = 10),
	list(REAGENT_ID_SLIMEJELLY = 10, REAGENT_ID_WATER = 10),
	list(REAGENT_ID_CARBON = 10, REAGENT_ID_TOXIN = 10),
	list(REAGENT_ID_NUTRIMENT = 5, REAGENT_ID_TOMATOJUICE = 10),
	list(REAGENT_ID_NUTRIMENT = 6, REAGENT_ID_TOMATOJUICE = 5, REAGENT_ID_IMIDAZOLINE = 5)))

/obj/item/reagent_containers/food/snacks/mysterysoup/proc/mystery_contents()
	var/list/recipes = TYPE_TABLE_GET(src, mystery_soup_recipes)
	return (mystery_recipe >= 1 && mystery_recipe <= length(recipes)) ? recipes[mystery_recipe] : null
