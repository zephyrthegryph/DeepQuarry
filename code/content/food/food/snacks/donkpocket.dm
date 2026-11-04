/obj/item/reagent_containers/food/snacks/donkpocket
	name = "\improper Donk-pocket"
	desc = "The food of choice for the seasoned traitor."
	icon_state = "donkpocket"
	filling_color = "#DEDEAB"
	nutriment_amt = 2
	nutriment_desc = list("heartiness" = 1, "dough" = 2)
	var/warm = FALSE

TYPE_TABLE_DECLARE(/obj/item/reagent_containers/food/snacks/donkpocket, donkpocket_heated_reagents, list(REAGENT_ID_TRICORDRAZINE = 5))

CAPABILITIES(/obj/item/reagent_containers/food/snacks/donkpocket)
	configure(atom_rules(price_tag = 1, description_fluff = "DONKpockets were originally a Nanotrasen product, an attempt to break into the food market controlled by Centauri Provisions. Somehow, Centauri wound up with the rights to the DONK brand, ending Nanotrasen's ambitions. They taste pretty okay."))
	configure(item_handling(center_x = 16, center_y = 10))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 2)))

/obj/item/reagent_containers/food/snacks/donkpocket/proc/heat()
	warm = 1
	for(var/reagent in TYPE_TABLE_GET(src, donkpocket_heated_reagents))
		reagents.add_reagent(reagent, TYPE_TABLE_GET(src, donkpocket_heated_reagents)[reagent])
	set_bitesize(6)
	name = "warm [name]"
	cooltime()

/obj/item/reagent_containers/food/snacks/donkpocket/proc/cooltime()
	if (src.warm)
		after(src, 420 SECONDS, PROC_REF(cool_down))
	return

/obj/item/reagent_containers/food/snacks/donkpocket/spicy
	name = "\improper Spicy-pocket"
	desc = "The classic snack food, now with a heat-activated spicy flair."
	icon_state = "donkpocketspicy"
	nutriment_amt = 2
	nutriment_desc = list("heartiness" = 1, "dough" = 2, "spice" = 1)

/obj/item/reagent_containers/food/snacks/donkpocket/teriyaki
	name = "\improper Teriyaki-pocket"
	desc = "An east-Asian take on the classic stationside snack."
	icon_state = "donkpocketteriyaki"
	nutriment_amt = 2
	nutriment_desc = list("meat" = 1, "dough" = 2, "soy sauce" = 2)

/obj/item/reagent_containers/food/snacks/donkpocket/pizza
	name = "\improper Pizza-pocket"
	desc = "Delicious, cheesy and surprisingly filling."
	icon_state = "donkpocketpizza"
	nutriment_amt = 2
	nutriment_desc = list("meat" = 1, "dough" = 2, REAGENT_ID_CHEESE= 2)

/obj/item/reagent_containers/food/snacks/donkpocket/honk
	name = "\improper Honk-pocket"
	desc = "The award-winning donk-pocket that won the hearts of clowns and humans alike."
	icon_state = "donkpocketbanana"
	nutriment_amt = 2
	nutriment_desc = list(REAGENT_ID_BANANA = 1, "dough" = 2, "children's antibiotics"= 1)

/obj/item/reagent_containers/food/snacks/donkpocket/berry
	name = "\improper Berry-pocket"
	desc = "A relentlessly sweet donk-pocket first created for use in Operation Dessert Storm."
	icon_state = "donkpocketberry"
	nutriment_amt = 2
	nutriment_desc = list("dough" = 2, "jam" = 2)

/obj/item/reagent_containers/food/snacks/donkpocket/gondola
	name = "\improper Gondola-pocket"
	desc = "The choice to use real gondola meat in the recipe is controversial, to say the least." //Only a monster would craft this.
	icon_state = "donkpocketberry"
	nutriment_amt = 2
	nutriment_desc = list("heartiness" = 1, "dough" = 2, "inner peace" = 1)

/obj/item/reagent_containers/food/snacks/donkpocket/dankpocket
	name = "\improper Dank-pocket"
	desc = "The food of choice for the seasoned botanist."
	icon_state = "dankpocket"
	nutriment_amt = 2
	nutriment_desc = list("heartiness" = 1, "dough" = 2)

TYPE_TABLE(/obj/item/reagent_containers/food/snacks/donkpocket/dankpocket, donkpocket_heated_reagents, list(REAGENT_ID_BLISS = 5))

/obj/item/reagent_containers/food/snacks/donkpocket/ascended
	name = "Donk-pocket EX"
	desc = "This donk-pocket has seen things beyond comprehension of mortals. It survived because the fire inside it burned brighter than fire around it."
	icon = 'icons/obj/food.dmi'
	icon_state = "donkpocket_ascended"
	nutriment_amt = 5
	nutriment_desc = list("burning fires of radioactive hell" = 20)

TYPE_TABLE(/obj/item/reagent_containers/food/snacks/donkpocket/ascended, donkpocket_heated_reagents, list(REAGENT_ID_SUPERMATTER = 1))

CAPABILITIES(/obj/item/reagent_containers/food/snacks/donkpocket/ascended)
	configure(reagents(add = list(REAGENT_ID_URANIUM = 3, REAGENT_ID_THERMITEV = 3)))

/obj/item/reagent_containers/food/snacks/donkpocket/proc/cool_down()
	if(!src?.reagents)
		return
	src.warm = 0
	for(var/reagent in TYPE_TABLE_GET(src, donkpocket_heated_reagents))
		src.reagents.del_reagent(reagent)
	src.name = initial(name)
