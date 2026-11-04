////////////////////ancient_vend (Hot Food - Old)////////////////////////////////////////////////////

/obj/item/reagent_containers/food/snacks/old
	name = "master old-food"
	desc = "they're all inedible and potentially dangerous items"
	nutriment_desc = list("rot" = 5, REAGENT_ID_MOLD = 5)
	nutriment_amt = 10
	bitesize = 3
	filling_color = "#336b42"

/obj/item/reagent_containers/food/snacks/old
	/// What it went bad with (rolls()): 5 units, and 5 of salmonella.
	var/old_taint

CAPABILITIES(/obj/item/reagent_containers/food/snacks/old)
	configure(item_handling(center_x = 15, center_y = 9))
	rolls(nameof(old_taint), pick_one(list(REAGENT_ID_FUEL, REAGENT_ID_AMATOXIN, REAGENT_ID_CARPOTOXIN, REAGENT_ID_ZOMBIEPOWDER, REAGENT_ID_CRYPTOBIOLIN, REAGENT_ID_PSILOCYBIN)))
	configure(reagents(contents_from = PROC_REF(old_contents)))

/obj/item/reagent_containers/food/snacks/old/proc/old_contents()
	return old_taint ? list("[old_taint]" = 5, REAGENT_ID_SALMONELLA = 5) : list(REAGENT_ID_SALMONELLA = 5)

/obj/item/reagent_containers/food/snacks/old/pizza
	name = "\improper Pizza!"
	desc = "It's so stale you could probably cut something with the cheese."
	icon_state = "ancient_pizza"

/obj/item/reagent_containers/food/snacks/old/burger
	name = "\improper Giga Burger!"
	desc = "At some point in time this probably looked delicious."
	icon_state = "ancient_burger"

/obj/item/reagent_containers/food/snacks/old/horseburger
	name = "\improper Horse Burger!"
	desc = "Even if you were hungry enough to eat a horse, it'd be a bad idea to eat this."
	icon_state = "ancient_horse_burger"

/obj/item/reagent_containers/food/snacks/old/fries
	name = "\improper Space Fries!"
	desc = "The salt appears to have preserved these, still stale and gross."
	icon_state = "ancient_fries"

/obj/item/reagent_containers/food/snacks/old/hotdog
	name = "\improper Space Dog!"
	desc = "This one is probably only marginally less safe to eat than when it was first created.."
	icon_state = "ancient_hotdog"

/obj/item/reagent_containers/food/snacks/old/taco
	name = "\improper Taco!"
	desc = "Interestingly, the shell has gone soft and the contents have gone stale."
	icon_state = "ancient_taco"
