
// see code/datums/recipe.dm


/* No telebacon. just no...
/transformation/kitchen/telebacon
	items = list(
		/obj/item/reagent_containers/food/snacks/meat,
		/obj/item/assembly/signaler
	)
	result = /obj/item/reagent_containers/food/snacks/telebacon

I said no!
/transformation/kitchen/syntitelebacon
	items = list(
		/obj/item/reagent_containers/food/snacks/meat/syntiflesh,
		/obj/item/assembly/signaler
	)
	result = /obj/item/reagent_containers/food/snacks/telebacon
*/

/transformation/kitchen/friedegg
CAPABILITIES(/transformation/kitchen/friedegg)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/friedegg, 1))))

/transformation/kitchen/boiledegg
CAPABILITIES(/transformation/kitchen/boiledegg)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/boiledegg, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/devilledegg
CAPABILITIES(/transformation/kitchen/devilledegg)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 2),
			reagent(REAGENT_ID_MAYO, 5),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/devilledegg, 1))))

// SPECIAL
/transformation/kitchen/donkpocket
CAPABILITIES(/transformation/kitchen/donkpocket)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donkpocket, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/donkpocket/proc/warm_up(obj/item/reagent_containers/food/snacks/donkpocket/being_cooked)
	being_cooked.heat()

/transformation/kitchen/donkpocket/make_food(obj/container as obj)
	. = ..(container)
	for (var/obj/item/reagent_containers/food/snacks/donkpocket/D in .)
		if (!D.warm)
			warm_up(D)

// This is necessary since this is a child object of the above recipe and we don't want donk pockets to need flour
// SPECIAL
/transformation/kitchen/donkpocket/warm
CAPABILITIES(/transformation/kitchen/donkpocket/warm)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/donkpocket, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donkpocket, 1))))

/transformation/kitchen/donkpocket/warm/make_food(obj/container)
	var/list/results = list()
	var/obj/item/reagent_containers/food/snacks/donkpocket/D = locate_in_list(container, /obj/item/reagent_containers/food/snacks/donkpocket)
	if(!D)
		return results
	if(!D.warm)
		warm_up(D)
	results.Add(D)
	return results

/transformation/kitchen/muffin
CAPABILITIES(/transformation/kitchen/muffin)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/muffin, 2)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/eggplantparm
CAPABILITIES(/transformation/kitchen/eggplantparm)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_EGGPLANT, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/eggplantparm, 1))))

/transformation/kitchen/soylenviridians
CAPABILITIES(/transformation/kitchen/soylenviridians)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 10),
			fruit_term(PLANT_SOYBEAN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/soylenviridians, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/soylentgreen
CAPABILITIES(/transformation/kitchen/soylentgreen)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/meat/human, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/human, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/soylentgreen, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/berryclafoutis
CAPABILITIES(/transformation/kitchen/berryclafoutis)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_BERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/berryclafoutis/berry, 1))))

/transformation/kitchen/poisonberryclafoutis
CAPABILITIES(/transformation/kitchen/poisonberryclafoutis)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_POISONBERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/berryclafoutis/poison, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/wingfangchu
CAPABILITIES(/transformation/kitchen/wingfangchu)
	configure(transformation(takes = list(reagent(REAGENT_ID_SOYSAUCE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/wingfangchu, 1))))

/transformation/kitchen/loadedbakedpotato
CAPABILITIES(/transformation/kitchen/loadedbakedpotato)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/loadedbakedpotato, 1))))

/transformation/kitchen/microfries
CAPABILITIES(/transformation/kitchen/microfries)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawsticks, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/microfries, 1)),
		cooks_in = MICROWAVE))

/transformation/kitchen/bangersandmash
CAPABILITIES(/transformation/kitchen/bangersandmash)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/mashedpotato, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bangersandmash, 1))))

/transformation/kitchen/cheesymash
CAPABILITIES(/transformation/kitchen/cheesymash)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/mashedpotato, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesymash, 1))))

/transformation/kitchen/blackpudding
CAPABILITIES(/transformation/kitchen/blackpudding)
	configure(transformation(takes = list(reagent(REAGENT_ID_BLOOD, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/blackpudding, 1))))

/transformation/kitchen/popcorn
CAPABILITIES(/transformation/kitchen/popcorn)
	configure(transformation(takes = list(fruit_term(PLANT_CORN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/popcorn, 1))))

/transformation/kitchen/fortunecookie
CAPABILITIES(/transformation/kitchen/fortunecookie)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/paper, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fortunecookie, 1))))

/transformation/kitchen/syntisteak
CAPABILITIES(/transformation/kitchen/syntisteak)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatsteak, 1))))

/transformation/kitchen/spacylibertyduff
CAPABILITIES(/transformation/kitchen/spacylibertyduff)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_VODKA, 5),
			reagent(REAGENT_ID_PSILOCYBIN, 5)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/spacylibertyduff, 1))))

/transformation/kitchen/amanitajelly
CAPABILITIES(/transformation/kitchen/amanitajelly)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_VODKA, 5),
			reagent(REAGENT_ID_AMATOXIN, 5)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/amanitajelly, 1))))

/transformation/kitchen/amanitajelly/make_food(obj/container as obj)
	. = ..(container)
	for(var/obj/item/reagent_containers/food/snacks/amanitajelly/being_cooked in .)
		being_cooked.reagents.del_reagent(REAGENT_ID_AMATOXIN)

/transformation/kitchen/meatballsoup
CAPABILITIES(/transformation/kitchen/meatballsoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatballsoup, 1))))

/transformation/kitchen/vegetablesoup
CAPABILITIES(/transformation/kitchen/vegetablesoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_POTATO, 1),
			fruit_term(PLANT_CORN, 1),
			fruit_term(PLANT_EGGPLANT, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/vegetablesoup, 1))))

/transformation/kitchen/nettlesoup
CAPABILITIES(/transformation/kitchen/nettlesoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			reagent(REAGENT_ID_EGG, 3),
			fruit_term(PLANT_NETTLE, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/nettlesoup, 1))))

/transformation/kitchen/wishsoup
CAPABILITIES(/transformation/kitchen/wishsoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 20)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/wishsoup, 1))))

/transformation/kitchen/hotchili
CAPABILITIES(/transformation/kitchen/hotchili)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/hotchili, 1))))

/transformation/kitchen/coldchili
CAPABILITIES(/transformation/kitchen/coldchili)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_ICECHILI, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/coldchili, 1))))

/transformation/kitchen/fishandchips
CAPABILITIES(/transformation/kitchen/fishandchips)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/fries, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fishandchips, 1))))

/transformation/kitchen/sandwich
CAPABILITIES(/transformation/kitchen/sandwich)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meatsteak, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sandwich, 1))))

/transformation/kitchen/peanutbutterjellysandwich
CAPABILITIES(/transformation/kitchen/peanutbutterjellysandwich)
	configure(transformation(takes = list(reagent(REAGENT_ID_CHERRYJELLY, 5),
			reagent(REAGENT_ID_PEANUTBUTTER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jellysandwich/peanutbutter, 1))))

/transformation/kitchen/clubsandwich
CAPABILITIES(/transformation/kitchen/clubsandwich)
	configure(transformation(takes = list(reagent(REAGENT_ID_MAYO, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/chicken, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_LETTUCE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/clubsandwich, 1))))

/transformation/kitchen/tomatosoup
CAPABILITIES(/transformation/kitchen/tomatosoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			fruit_term(PLANT_TOMATO, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tomatosoup, 1))))

/transformation/kitchen/rofflewaffles
CAPABILITIES(/transformation/kitchen/rofflewaffles)
	configure(transformation(takes = list(reagent(REAGENT_ID_PSILOCYBIN, 5),
			reagent(REAGENT_ID_SUGAR, 10),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/rofflewaffles, 2))))

/transformation/kitchen/stew
CAPABILITIES(/transformation/kitchen/stew)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_POTATO, 1),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_EGGPLANT, 1),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/stew, 1))))

/transformation/kitchen/slimetoast
CAPABILITIES(/transformation/kitchen/slimetoast)
	configure(transformation(takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jelliedtoast/slime, 1))))

/transformation/kitchen/jelliedtoast
CAPABILITIES(/transformation/kitchen/jelliedtoast)
	configure(transformation(takes = list(reagent(REAGENT_ID_CHERRYJELLY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jelliedtoast/cherry, 1))))

/transformation/kitchen/milosoup
CAPABILITIES(/transformation/kitchen/milosoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/soydope, 1),
			item_term(/obj/item/reagent_containers/food/snacks/soydope, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/milosoup, 1))))

/transformation/kitchen/stewedsoymeat
CAPABILITIES(/transformation/kitchen/stewedsoymeat)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/soydope, 1),
			item_term(/obj/item/reagent_containers/food/snacks/soydope, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/stewedsoymeat, 1))))

/transformation/kitchen/boiledspagetti
CAPABILITIES(/transformation/kitchen/boiledspagetti)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/boiledspagetti, 1))))

/transformation/kitchen/boiledrice
CAPABILITIES(/transformation/kitchen/boiledrice)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_RICE, 10)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/boiledrice, 1))))

/transformation/kitchen/ricepudding
CAPABILITIES(/transformation/kitchen/ricepudding)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_RICE, 10)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ricepudding, 1))))

/transformation/kitchen/pastatomato
CAPABILITIES(/transformation/kitchen/pastatomato)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			fruit_term(PLANT_TOMATO, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/pastatomato, 1))))

/transformation/kitchen/meatballspagetti
CAPABILITIES(/transformation/kitchen/meatballspagetti)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatballspagetti, 1))))

/transformation/kitchen/spesslaw
CAPABILITIES(/transformation/kitchen/spesslaw)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/spesslaw, 1))))

// Makes sense seeing as how it's just syrup on the exterior
/transformation/kitchen/candiedapple
CAPABILITIES(/transformation/kitchen/candiedapple)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			fruit_term(PLANT_APPLE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/candiedapple, 1))))

// Since caramel can be made with milk I thought this was appropriate
/transformation/kitchen/caramelapple
CAPABILITIES(/transformation/kitchen/caramelapple)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			fruit_term(PLANT_APPLE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/caramelapple, 1))))

/transformation/kitchen/twobread
CAPABILITIES(/transformation/kitchen/twobread)
	configure(transformation(takes = list(reagent(REAGENT_ID_REDWINE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/twobread, 1))))

/transformation/kitchen/slimesandwich
CAPABILITIES(/transformation/kitchen/slimesandwich)
	configure(transformation(takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jellysandwich/slime, 1))))

/transformation/kitchen/cherrysandwich
CAPABILITIES(/transformation/kitchen/cherrysandwich)
	configure(transformation(takes = list(reagent(REAGENT_ID_CHERRYJELLY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jellysandwich/cherry, 1))))

/transformation/kitchen/bloodsoup
CAPABILITIES(/transformation/kitchen/bloodsoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_BLOOD, 30)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bloodsoup, 1))))

/transformation/kitchen/slimesoup
CAPABILITIES(/transformation/kitchen/slimesoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/slimesoup, 1))))

/transformation/kitchen/boiledslimeextract
CAPABILITIES(/transformation/kitchen/boiledslimeextract)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/slime_extract, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/boiledslimecore, 1))))

/transformation/kitchen/chocolateegg
CAPABILITIES(/transformation/kitchen/chocolateegg)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chocolateegg, 1))))

/transformation/kitchen/sausage
CAPABILITIES(/transformation/kitchen/sausage)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sausage, 2))))

/transformation/kitchen/kudzudonburi
CAPABILITIES(/transformation/kitchen/kudzudonburi)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 10),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_KUDZU, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/kudzudonburi, 1))))

/transformation/kitchen/mysterysoup
CAPABILITIES(/transformation/kitchen/mysterysoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			reagent(REAGENT_ID_EGG, 3),
			item_term(/obj/item/reagent_containers/food/snacks/badrecipe, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mysterysoup, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/plumphelmetbiscuit
CAPABILITIES(/transformation/kitchen/plumphelmetbiscuit)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_FLOUR, 5),
			fruit_term(PLANT_PLUMPHELMET, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit, 2))))

/transformation/kitchen/mushroomsoup
CAPABILITIES(/transformation/kitchen/mushroomsoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_MILK, 5),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mushroomsoup, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/chawanmushi
CAPABILITIES(/transformation/kitchen/chawanmushi)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_SOYSAUCE, 5),
			reagent(REAGENT_ID_EGG, 6),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chawanmushi, 1))))

/transformation/kitchen/beetsoup
CAPABILITIES(/transformation/kitchen/beetsoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			fruit_term(PLANT_WHITEBEET, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/beetsoup, 1))))

/transformation/kitchen/tossedsalad
CAPABILITIES(/transformation/kitchen/tossedsalad)
	configure(transformation(takes = list(fruit_term(PLANT_LETTUCE, 2),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_APPLE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tossedsalad, 1))))

/transformation/kitchen/flowersalad
CAPABILITIES(/transformation/kitchen/flowersalad)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedsunflower, 1),
			fruit_term(PLANT_HAREBELLS, 1),
			fruit_term(PLANT_POPPIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/flowerchildsalad, 1))))

/transformation/kitchen/rosesalad
CAPABILITIES(/transformation/kitchen/rosesalad)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedsunflower, 1),
			fruit_term(PLANT_HAREBELLS, 1),
			fruit_term(PLANT_ROSE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/rosesalad, 1))))

/transformation/kitchen/aesirsalad
CAPABILITIES(/transformation/kitchen/aesirsalad)
	configure(transformation(takes = list(fruit_term(PLANT_GOLDAPPLE, 1),
			fruit_term(PLANT_AMBROSIADEUS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/aesirsalad, 1))))

/transformation/kitchen/validsalad
CAPABILITIES(/transformation/kitchen/validsalad)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			fruit_term(PLANT_POTATO, 1),
			fruit_term(PLANT_AMBROSIA, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/validsalad, 1))))

/transformation/kitchen/dankpocket
CAPABILITIES(/transformation/kitchen/dankpocket)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			fruit_term(PLANT_AMBROSIA, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donkpocket/dankpocket, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/validsalad/make_food(obj/container as obj)
	. = ..(container)
	for (var/obj/item/reagent_containers/food/snacks/validsalad/being_cooked in .)
		being_cooked.reagents.del_reagent(REAGENT_ID_TOXIN)

/transformation/kitchen/stuffing
CAPABILITIES(/transformation/kitchen/stuffing)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/stuffing, 2))))

/transformation/kitchen/mashedpotato
CAPABILITIES(/transformation/kitchen/mashedpotato)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/spreads, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mashedpotato, 1))))

/transformation/kitchen/icecreamsandwich
CAPABILITIES(/transformation/kitchen/icecreamsandwich)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_ICE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/icecream, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/icecreamsandwich, 1))))

/transformation/kitchen/onionsoup
CAPABILITIES(/transformation/kitchen/onionsoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			fruit_term(PLANT_ONION, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/soup/onion, 1))))

/transformation/kitchen/microwavebun
CAPABILITIES(/transformation/kitchen/microwavebun)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 3))))

/transformation/kitchen/microwaveflatbread
CAPABILITIES(/transformation/kitchen/microwaveflatbread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/flatbread, 1))))

/transformation/kitchen/meatball
CAPABILITIES(/transformation/kitchen/meatball)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawmeatball, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatball, 1))))

/transformation/kitchen/cutlet
CAPABILITIES(/transformation/kitchen/cutlet)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawcutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1))))

// Other recipies are other oils
/transformation/kitchen/roastedcornsunflowerseeds
CAPABILITIES(/transformation/kitchen/roastedcornsunflowerseeds)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_CORNOIL, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawsunflower, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedsunflower, 2)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/roastedsunflowerseeds
CAPABILITIES(/transformation/kitchen/roastedsunflowerseeds)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_COOKINGOIL, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawsunflower, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedsunflower, 2))))

// Other recipies are other oils
/transformation/kitchen/roastedpeanutsunflowerseeds
CAPABILITIES(/transformation/kitchen/roastedpeanutsunflowerseeds)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_PEANUTOIL, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawsunflower, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedsunflower, 2)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/roastedpeanuts
CAPABILITIES(/transformation/kitchen/roastedpeanuts)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 2),
			reagent(REAGENT_ID_COOKINGOIL, 1),
			fruit_term(PLANT_PEANUT, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedpeanuts, 2))))

// other recipies are just other oils
/transformation/kitchen/roastedpeanutscorn
CAPABILITIES(/transformation/kitchen/roastedpeanutscorn)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 2),
			reagent(REAGENT_ID_CORNOIL, 1),
			fruit_term(PLANT_PEANUT, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedpeanuts, 2)),
		wiki = WIKI_SPOILER))

// other recipies are just other oils
/transformation/kitchen/roastedpeanutspeanut
CAPABILITIES(/transformation/kitchen/roastedpeanutspeanut)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 2),
			reagent(REAGENT_ID_PEANUTOIL, 1),
			fruit_term(PLANT_PEANUT, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastedpeanuts, 2)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/mint
CAPABILITIES(/transformation/kitchen/mint)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_FROSTOIL, 5)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mint, 1))))

/transformation/kitchen/sashimi
CAPABILITIES(/transformation/kitchen/sashimi)
	configure(transformation(takes = list(reagent(REAGENT_ID_SOYSAUCE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sashimi, 1))))

/transformation/kitchen/benedict
CAPABILITIES(/transformation/kitchen/benedict)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/friedegg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/benedict, 1))))

/transformation/kitchen/bakedbeans
CAPABILITIES(/transformation/kitchen/bakedbeans)
	configure(transformation(takes = list(reagent(REAGENT_ID_KETCHUP, 5),
			fruit_term(PLANT_SOYBEAN, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/beans, 1))))

/transformation/kitchen/sugarcookie
CAPABILITIES(/transformation/kitchen/sugarcookie)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_EGG, 3),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sugarcookie, 4))))

/transformation/kitchen/berrymuffin
CAPABILITIES(/transformation/kitchen/berrymuffin)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_BERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/berrymuffin/berry, 2))))

/transformation/kitchen/poisonberrymuffin
CAPABILITIES(/transformation/kitchen/poisonberrymuffin)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_POISONBERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/berrymuffin/poison, 2)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/ghostmuffin
CAPABILITIES(/transformation/kitchen/ghostmuffin)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/ectoplasm, 1),
			fruit_term(PLANT_BERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ghostmuffin/berry, 2))))

/transformation/kitchen/poisonghostmuffin
CAPABILITIES(/transformation/kitchen/poisonghostmuffin)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/ectoplasm, 1),
			fruit_term(PLANT_POISONBERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ghostmuffin/poison, 2)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/eggroll
CAPABILITIES(/transformation/kitchen/eggroll)
	configure(transformation(takes = list(reagent(REAGENT_ID_SOYSAUCE, 10),
			item_term(/obj/item/reagent_containers/food/snacks/friedegg, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/eggroll, 1))))

/transformation/kitchen/fruitsalad
CAPABILITIES(/transformation/kitchen/fruitsalad)
	configure(transformation(takes = list(fruit_term(PLANT_ORANGE, 1),
			fruit_term(PLANT_APPLE, 1),
			fruit_term(PLANT_GRAPES, 1),
			fruit_term(PLANT_WATERMELON, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fruitsalad, 1))))

/transformation/kitchen/eggbowl
CAPABILITIES(/transformation/kitchen/eggbowl)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_RICE, 10),
			reagent(REAGENT_ID_EGG, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/eggbowl, 1))))

/transformation/kitchen/porkbowl
CAPABILITIES(/transformation/kitchen/porkbowl)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_RICE, 10),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/porkbowl, 1))))

/transformation/kitchen/cubannachos
CAPABILITIES(/transformation/kitchen/cubannachos)
	configure(transformation(takes = list(reagent(REAGENT_ID_KETCHUP, 5),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cubannachos, 1))))

/transformation/kitchen/curryrice
CAPABILITIES(/transformation/kitchen/curryrice)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 10),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/curryrice, 1))))

/transformation/kitchen/piginblanket
CAPABILITIES(/transformation/kitchen/piginblanket)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/piginblanket, 1))))

/transformation/kitchen/bagelplain
CAPABILITIES(/transformation/kitchen/bagelplain)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bagelplain, 1))))

/transformation/kitchen/bagelsunflower
CAPABILITIES(/transformation/kitchen/bagelsunflower)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawsunflower, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bagelsunflower, 1))))

/transformation/kitchen/bagelcheese
CAPABILITIES(/transformation/kitchen/bagelcheese)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bagelcheese, 1))))

/transformation/kitchen/bagelraisin
CAPABILITIES(/transformation/kitchen/bagelraisin)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/no_raisin, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bagelraisin, 1))))

/transformation/kitchen/bagelpoppy
CAPABILITIES(/transformation/kitchen/bagelpoppy)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			fruit_term(PLANT_POPPIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bagelpoppy, 1))))

/transformation/kitchen/bageleverything
CAPABILITIES(/transformation/kitchen/bageleverything)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/fuel_assembly/supermatter, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bageleverything, 1))))

/transformation/kitchen/bageltwo
CAPABILITIES(/transformation/kitchen/bageltwo)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/soulstone, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bageltwo, 1))))

//Recipes that use RECIPE_REAGENT_REPLACE will
//simplify the end product and balance the amount of reagents
//in some foods. Many require the space spice reagent/condiment
//to reduce the risk of future recipe conflicts.

// Simplify end product
/transformation/kitchen/redcurry
CAPABILITIES(/transformation/kitchen/redcurry)
	configure(transformation(takes = list(reagent(REAGENT_ID_CREAM, 5),
			reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_RICE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/redcurry, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/greencurry
CAPABILITIES(/transformation/kitchen/greencurry)
	configure(transformation(takes = list(reagent(REAGENT_ID_CREAM, 5),
			reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_RICE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/greencurry, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/yellowcurry
CAPABILITIES(/transformation/kitchen/yellowcurry)
	configure(transformation(takes = list(reagent(REAGENT_ID_CREAM, 5),
			reagent(REAGENT_ID_SPACESPICE, 2),
			reagent(REAGENT_ID_RICE, 5),
			fruit_term(PLANT_PEANUT, 2),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/yellowcurry, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/bearchili
CAPABILITIES(/transformation/kitchen/bearchili)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bearmeat, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bearchili, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/bearstew
CAPABILITIES(/transformation/kitchen/bearstew)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/bearmeat, 1),
			fruit_term(PLANT_POTATO, 1),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_EGGPLANT, 1),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bearstew, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/bibimbap
CAPABILITIES(/transformation/kitchen/bibimbap)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 5),
			reagent(REAGENT_ID_SPACESPICE, 2),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_CABBAGE, 1),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bibimbap, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/friedrice
CAPABILITIES(/transformation/kitchen/friedrice)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_RICE, 10),
			reagent(REAGENT_ID_SOYSAUCE, 5),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/friedrice, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/lomein
CAPABILITIES(/transformation/kitchen/lomein)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			reagent(REAGENT_ID_SOYSAUCE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/lomein, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/chickennoodlesoup
CAPABILITIES(/transformation/kitchen/chickennoodlesoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawcutlet, 1),
			fruit_term(PLANT_CARROT, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chickennoodlesoup, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Simplify end product
/transformation/kitchen/chilicheesefries
CAPABILITIES(/transformation/kitchen/chilicheesefries)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/fries, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/hotchili, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chilicheesefries, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Get that rice and wine outta here
/transformation/kitchen/risotto
CAPABILITIES(/transformation/kitchen/risotto)
	configure(transformation(takes = list(reagent(REAGENT_ID_REDWINE, 5),
			reagent(REAGENT_ID_RICE, 10),
			reagent(REAGENT_ID_SPACESPICE, 1),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/risotto, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Get that water outta here
/transformation/kitchen/poachedegg
CAPABILITIES(/transformation/kitchen/poachedegg)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/poachedegg, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/nugget
CAPABILITIES(/transformation/kitchen/nugget)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/meat/chicken, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/nugget, 3)),
		mix = RECIPE_REAGENT_REPLACE))

// Chip update
// no gross flour or water
/transformation/kitchen/microwavetortilla
CAPABILITIES(/transformation/kitchen/microwavetortilla)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 5),
			reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 3)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/taco
CAPABILITIES(/transformation/kitchen/taco)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/taco, 1))))

/transformation/kitchen/chips
CAPABILITIES(/transformation/kitchen/chips)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chipplate, 1))))

/transformation/kitchen/nachos
CAPABILITIES(/transformation/kitchen/nachos)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/chipplate, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chipplate/nachos, 1))))

// Ingredients are mixed together.
/transformation/kitchen/salsa
CAPABILITIES(/transformation/kitchen/salsa)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_LIME, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/dip/salsa, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Ingredients are mixed together.
/transformation/kitchen/guac
CAPABILITIES(/transformation/kitchen/guac)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_LIME, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/dip/guac, 1)),
		mix = RECIPE_REAGENT_REPLACE))

// Ingredients are mixed together.
/transformation/kitchen/cheesesauce
CAPABILITIES(/transformation/kitchen/cheesesauce)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/dip, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/burrito
CAPABILITIES(/transformation/kitchen/burrito)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burrito, 1))))

/transformation/kitchen/burrito_vegan
CAPABILITIES(/transformation/kitchen/burrito_vegan)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burrito_vegan, 1))))

/transformation/kitchen/burrito_cheese
CAPABILITIES(/transformation/kitchen/burrito_cheese)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burrito_cheese, 1))))

/transformation/kitchen/burrito_cheese_spicy
CAPABILITIES(/transformation/kitchen/burrito_cheese_spicy)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_CHILI, 2),
			fruit_term(PLANT_SOYBEAN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burrito_cheese_spicy, 1))))

// Already hot sauce
/transformation/kitchen/burrito_hell
CAPABILITIES(/transformation/kitchen/burrito_hell)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			fruit_term(PLANT_SOYBEAN, 1),
			fruit_term(PLANT_CHILI, 10)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burrito_hell, 1)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/meatburrito
CAPABILITIES(/transformation/kitchen/meatburrito)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			fruit_term(PLANT_SOYBEAN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatburrito, 1))))

/transformation/kitchen/cheeseburrito
CAPABILITIES(/transformation/kitchen/cheeseburrito)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_SOYBEAN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cheeseburrito, 1))))

/transformation/kitchen/fuegoburrito
CAPABILITIES(/transformation/kitchen/fuegoburrito)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			fruit_term(PLANT_SOYBEAN, 1),
			fruit_term(PLANT_CHILI, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fuegoburrito, 1))))

/transformation/kitchen/breakfast_wrap
CAPABILITIES(/transformation/kitchen/breakfast_wrap)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/breakfast_wrap, 1))))

/transformation/kitchen/burrito_mystery
CAPABILITIES(/transformation/kitchen/burrito_mystery)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/mysterysoup, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burrito_mystery, 1))))

/transformation/kitchen/baconmicrowave
CAPABILITIES(/transformation/kitchen/baconmicrowave)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon/microwave, 1))))

/transformation/kitchen/chilied_eggs
CAPABILITIES(/transformation/kitchen/chilied_eggs)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/hotchili, 1),
			item_term(/obj/item/reagent_containers/food/snacks/boiledegg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/boiledegg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/boiledegg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chilied_eggs, 1))))

/transformation/kitchen/red_sun_special
CAPABILITIES(/transformation/kitchen/red_sun_special)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sausage, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/red_sun_special, 1))))

/transformation/kitchen/hatchling_suprise
CAPABILITIES(/transformation/kitchen/hatchling_suprise)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/poachedegg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/hatchling_suprise, 1))))

/transformation/kitchen/riztizkzi_sea
CAPABILITIES(/transformation/kitchen/riztizkzi_sea)
	configure(transformation(takes = list(reagent(REAGENT_ID_BLOOD, 15),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/riztizkzi_sea, 1))))

/transformation/kitchen/father_breakfast
CAPABILITIES(/transformation/kitchen/father_breakfast)
	configure(transformation(takes = list(reagent(REAGENT_ID_EGG, 6),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatsteak, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/father_breakfast, 1))))

/transformation/kitchen/stuffed_meatball
CAPABILITIES(/transformation/kitchen/stuffed_meatball)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/stuffed_meatball, 2))))

/transformation/kitchen/egg_pancake
CAPABILITIES(/transformation/kitchen/egg_pancake)
	configure(transformation(takes = list(reagent(REAGENT_ID_EGG, 6),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatball, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/egg_pancake, 1))))

/transformation/kitchen/bacon_stick
CAPABILITIES(/transformation/kitchen/bacon_stick)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/boiledegg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon_stick, 1))))

/transformation/kitchen/bacon_and_eggs
CAPABILITIES(/transformation/kitchen/bacon_and_eggs)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/friedegg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon_and_eggs, 1))))

/transformation/kitchen/ntmuffin
CAPABILITIES(/transformation/kitchen/ntmuffin)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1),
			item_term(/obj/item/reagent_containers/food/snacks/friedegg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/nt_muffin, 1))))

/transformation/kitchen/fish_taco
CAPABILITIES(/transformation/kitchen/fish_taco)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_LEMON, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fish_taco, 1))))

/transformation/kitchen/blt
CAPABILITIES(/transformation/kitchen/blt)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_LETTUCE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/blt, 1))))

/transformation/kitchen/gigapuddi
CAPABILITIES(/transformation/kitchen/gigapuddi)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 15),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/gigapuddi, 1))))

/transformation/kitchen/gigapuddi/happy
CAPABILITIES(/transformation/kitchen/gigapuddi/happy)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 15),
			reagent(REAGENT_ID_SUGAR, 5),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/gigapuddi/happy, 1))))

// Imported food from old code
/transformation/kitchen/gigapuddi/anger
CAPABILITIES(/transformation/kitchen/gigapuddi/anger)
	configure(transformation(takes = list(reagent(REAGENT_ID_MILK, 15),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/gigapuddi/anger, 1))))
/transformation/kitchen/sauerkraut
CAPABILITIES(/transformation/kitchen/sauerkraut)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 3),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sauerkraut, 1))))

/transformation/kitchen/tamales
CAPABILITIES(/transformation/kitchen/tamales)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_CORN, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tamales, 1))))

/transformation/kitchen/bigos
CAPABILITIES(/transformation/kitchen/bigos)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 5),
			reagent(REAGENT_ID_WATER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/sauerkraut, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1),
			fruit_term(PLANT_ONION, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bigos, 1))))

/transformation/kitchen/concha
CAPABILITIES(/transformation/kitchen/concha)
	configure(transformation(takes = list(reagent(REAGENT_ID_BERRYJUICE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/concha, 1))))

/transformation/kitchen/pandenata
CAPABILITIES(/transformation/kitchen/pandenata)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 10),
			reagent(REAGENT_ID_CREAM, 5),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1),
			item_term(/obj/item/reagent_containers/food/snacks/doughslice, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/pandenata, 1))))

/transformation/kitchen/tocino
CAPABILITIES(/transformation/kitchen/tocino)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 5),
			reagent(REAGENT_ID_REDWINE, 5),
			item_term(/obj/item/reagent_containers/food/snacks/rawcutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tocino, 1))))

/transformation/kitchen/garlicbread
CAPABILITIES(/transformation/kitchen/garlicbread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			fruit_term(PLANT_ONION, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/garlicbread, 1))))

/transformation/kitchen/plumpburger
CAPABILITIES(/transformation/kitchen/plumpburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			fruit_term(PLANT_PLUMPHELMET, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/plumpburger, 1))))

/transformation/kitchen/wataur
CAPABILITIES(/transformation/kitchen/wataur)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 100)),
		makes = list(item_term(/obj/item/reagent_containers/food/drinks/cans/waterbottle/wataur, 1))))

/transformation/kitchen/bigbeanburrito
CAPABILITIES(/transformation/kitchen/bigbeanburrito)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meatburrito, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawcutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			fruit_term(PLANT_SOYBEAN, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/slice/bigbeanburrito, 1))))

/transformation/kitchen/supremoburrito
CAPABILITIES(/transformation/kitchen/supremoburrito)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/slice/bigbeanburrito, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/cheesewheel, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tortilla, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_SOYBEAN, 3),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/supremoburrito, 1))))

/transformation/kitchen/steamtealeaf
CAPABILITIES(/transformation/kitchen/steamtealeaf)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 5),
			fruit_term(PLANT_TEA, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/steamtealeaf, 1))))

// TODO: Figure out how to make this recipe with a drying rack.
/transformation/kitchen/greentealeaf
CAPABILITIES(/transformation/kitchen/greentealeaf)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/steamrolltealeaf, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/greentealeaf, 1))))

// No actual reagents since it's meant to be a cooking item
/transformation/kitchen/butterscotch
CAPABILITIES(/transformation/kitchen/butterscotch)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 10),
			reagent(REAGENT_ID_CREAM, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spreads/butter, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/butterscotch, 2)),
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/hotbuttericecream
CAPABILITIES(/transformation/kitchen/hotbuttericecream)
	configure(transformation(takes = list(reagent(REAGENT_ID_ICE, 5),
			reagent(REAGENT_ID_CREAM, 5),
			item_term(/obj/item/reagent_containers/food/snacks/spreads/butter, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/hotbuttericecream, 1))))


/*
/transformation/kitchen/unique_name
	fruit = list("example_fruit1" = 1, "example_fruit2" = 2)
	reagents = list("example_reagent1" = 10, "example_reagent2" = 5)
	items = list(
		/obj/item/reagent_containers/food/snacks/meat/imaginary_meat_ingredient,
		/obj/item/reagent_containers/food/snacks/meat/this_won't_compile
	)
	result = /obj/item/reagent_containers/food/snacks/path_to_some_food
*/
// All of this shit needs to be gone through and reorganized into different recipes per machine - Rykka 7/16/2020

/transformation/kitchen/sushi
CAPABILITIES(/transformation/kitchen/sushi)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 20),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/sushi, 1))))

/transformation/kitchen/goulash
CAPABILITIES(/transformation/kitchen/goulash)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cutlet, 1),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/goulash, 1))))

/transformation/kitchen/donerkebab
CAPABILITIES(/transformation/kitchen/donerkebab)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meatsteak, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			fruit_term(PLANT_TOMATO, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/donerkebab, 1))))


/transformation/kitchen/roastbeef
CAPABILITIES(/transformation/kitchen/roastbeef)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_CARROT, 2),
			fruit_term(PLANT_POTATO, 2)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roastbeef, 1))))

/transformation/kitchen/reishicup
CAPABILITIES(/transformation/kitchen/reishicup)
	configure(transformation(takes = list(reagent(REAGENT_ID_PSILOCYBIN, 3),
			reagent(REAGENT_ID_SUGAR, 3),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/reishicup, 1))))

/transformation/kitchen/hotandsoursoup
CAPABILITIES(/transformation/kitchen/hotandsoursoup)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 2),
			reagent(REAGENT_ID_BLACKPEPPER, 2),
			reagent(REAGENT_ID_WATER, 10),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			fruit_term(PLANT_CABBAGE, 1),
			fruit_term(PLANT_MUSHROOMS, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/hotandsoursoup, 1))))

/transformation/kitchen/kitsuneudon
CAPABILITIES(/transformation/kitchen/kitsuneudon)
	configure(transformation(takes = list(reagent(REAGENT_ID_EGG, 3),
			item_term(/obj/item/reagent_containers/food/snacks/spagetti, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/kitsuneudon, 1))))

/transformation/kitchen/pillbugball
CAPABILITIES(/transformation/kitchen/pillbugball)
	configure(transformation(takes = list(reagent(REAGENT_ID_CARBON, 5),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bugball, 1))))

/transformation/kitchen/mammi
CAPABILITIES(/transformation/kitchen/mammi)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 10),
			reagent(REAGENT_ID_FLOUR, 10),
			reagent(REAGENT_ID_MILK, 5),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			fruit_term(PLANT_ORANGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mammi, 1))))

/transformation/kitchen/makaroni
CAPABILITIES(/transformation/kitchen/makaroni)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 15),
			reagent(REAGENT_ID_MILK, 5),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/egg, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/makaroni, 1))))

// Secretish? Just assume carp is fish anyway
/transformation/kitchen/carpsushi
CAPABILITIES(/transformation/kitchen/carpsushi)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 20),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_CABBAGE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/sushi, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/lobster
CAPABILITIES(/transformation/kitchen/lobster)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/lobster, 1),
			fruit_term(PLANT_LEMON, 1),
			fruit_term(PLANT_LETTUCE, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/lobstercooked, 1))))

/transformation/kitchen/cuttlefish
CAPABILITIES(/transformation/kitchen/cuttlefish)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cuttlefish, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cuttlefishcooked, 1))))

/transformation/kitchen/monkfish
CAPABILITIES(/transformation/kitchen/monkfish)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/monkfishfillet, 1),
			fruit_term(PLANT_CHILI, 1),
			fruit_term(PLANT_ONION, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkfishcooked, 1))))

/transformation/kitchen/sharksteak
CAPABILITIES(/transformation/kitchen/sharksteak)
	configure(transformation(takes = list(reagent(REAGENT_ID_BLACKPEPPER, 1),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat/fish/sharkmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sharkmeatcooked, 1))))

/transformation/kitchen/sharkdip
CAPABILITIES(/transformation/kitchen/sharkdip)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat/fish/sharkmeat, 1),
			fruit_term(PLANT_CHILI, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sharkmeatdip, 1))))

/transformation/kitchen/sharkcubes
CAPABILITIES(/transformation/kitchen/sharkcubes)
	configure(transformation(takes = list(reagent(REAGENT_ID_SOYSAUCE, 5),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat/fish/sharkmeat, 1),
			fruit_term(PLANT_POTATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sharkmeatcubes, 1))))

//// food cubes

// labor intensive
/transformation/kitchen/foodcubes
CAPABILITIES(/transformation/kitchen/foodcubes)
	configure(transformation(takes = list(reagent(REAGENT_ID_ENZYME, 20),
			reagent(REAGENT_ID_VIRUSFOOD, 5),
			reagent(REAGENT_ID_NUTRIMENT, 15),
			reagent(REAGENT_ID_PROTEIN, 15)),
		makes = list(item_term(/obj/item/storage/box/wings/tray, 1))))

/transformation/kitchen/bucket
CAPABILITIES(/transformation/kitchen/bucket)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			fruit_term(PLANT_DURIAN, 1)),
		makes = list(item_term(/obj/item/storage/box/wings/bucket, 1))))

/transformation/kitchen/grub_pink
CAPABILITIES(/transformation/kitchen/grub_pink)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/grub, 1),
			fruit_term(PLANT_CHERRY, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/grub_pink, 1))))

/transformation/kitchen/grub_blue
CAPABILITIES(/transformation/kitchen/grub_blue)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/grub, 1),
			fruit_term(PLANT_BERRIES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/grub_blue, 1))))

/transformation/kitchen/grub_purple
CAPABILITIES(/transformation/kitchen/grub_purple)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/grub, 1),
			fruit_term(PLANT_GRAPES, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/grub_purple, 1))))

/transformation/kitchen/honey_candy
CAPABILITIES(/transformation/kitchen/honey_candy)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_NUTRIMENT, 5)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/honey_candy, 1))))

/transformation/kitchen/altevian_steak
CAPABILITIES(/transformation/kitchen/altevian_steak)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/ratprotein, 1),
			item_term(/obj/item/reagent_containers/food/snacks/ratveggies, 1),
			item_term(/obj/item/reagent_containers/food/snacks/ratliquid, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ratsteak, 1))))
