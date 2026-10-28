/transformation/chem/instant/food

CAPABILITIES(/transformation/chem/instant/food)
	configure(transformation(wiki = WIKI_FOOD))

/transformation/chem/instant/food/hell_ramen

CAPABILITIES(/transformation/chem/instant/food/hell_ramen)
	configure(transformation(name = REAGENT_HELLRAMEN, id = REAGENT_ID_HELLRAMEN,
		takes = list(reagent(REAGENT_ID_CAPSAICIN, 1), reagent(REAGENT_ID_HOTRAMEN, 6)),
		makes = list(reagent(REAGENT_ID_HELLRAMEN, 6))))

/transformation/chem/instant/food/tofu

CAPABILITIES(/transformation/chem/instant/food/tofu)
	configure(transformation(name = "Tofu", id = REAGENT_ID_TOFU, takes = list(reagent(REAGENT_ID_SOYMILK, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), made = 1,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/tofu, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/chocolate_bar

CAPABILITIES(/transformation/chem/instant/food/chocolate_bar)
	configure(transformation(name = "Chocolate Bar Soy", id = "chocolate_bar_soy",
		takes = list(reagent(REAGENT_ID_SOYMILK, 2), reagent(REAGENT_ID_COCO, 2), reagent(REAGENT_ID_SUGAR, 2)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), made = 1,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/chocolatebar, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/chocolate_bar2

CAPABILITIES(/transformation/chem/instant/food/chocolate_bar2)
	configure(transformation(name = "Chocolate Bar Milk", id = "chocolate_bar_milk",
		takes = list(reagent(REAGENT_ID_MILK, 2), reagent(REAGENT_ID_COCO, 2), reagent(REAGENT_ID_SUGAR, 2)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), made = 1,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/chocolatebar, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/cookingoilcorn

CAPABILITIES(/transformation/chem/instant/food/cookingoilcorn)
	configure(transformation(name = "corn " + REAGENT_COOKINGOIL, id = "cookingoilcorn", takes = list(reagent(REAGENT_ID_CORNOIL, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), blocked_by = list(reagent(REAGENT_ID_FLOUR, 1)),
		makes = list(reagent(REAGENT_ID_COOKINGOIL, 10))))

/transformation/chem/instant/food/cookingoilpeanut

CAPABILITIES(/transformation/chem/instant/food/cookingoilpeanut)
	configure(transformation(name = "peanut " + REAGENT_ID_COOKINGOIL, id = "cookingoilpeanut", takes = list(reagent(REAGENT_ID_PEANUTOIL, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)),
		blocked_by = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_SODIUMCHLORIDE, 1)),
		makes = list(reagent(REAGENT_ID_COOKINGOIL, 10))))

/transformation/chem/instant/food/soysauce

CAPABILITIES(/transformation/chem/instant/food/soysauce)
	configure(transformation(name = REAGENT_SOYSAUCE, id = REAGENT_ID_SOYSAUCE,
		takes = list(reagent(REAGENT_ID_SOYMILK, 4), reagent(REAGENT_ID_SACID, 1)), makes = list(reagent(REAGENT_ID_SOYSAUCE, 5))))

/transformation/chem/instant/food/ketchup

CAPABILITIES(/transformation/chem/instant/food/ketchup)
	configure(transformation(name = REAGENT_KETCHUP, id = REAGENT_ID_KETCHUP,
		takes = list(reagent(REAGENT_ID_TOMATOJUICE, 2), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_KETCHUP, 4))))

/transformation/chem/instant/food/barbecue

CAPABILITIES(/transformation/chem/instant/food/barbecue)
	configure(transformation(name = REAGENT_BARBECUE, id = REAGENT_ID_BARBECUE,
		takes = list(reagent(REAGENT_ID_TOMATOJUICE, 2), reagent(REAGENT_ID_APPLEJUICE, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_SPACESPICE, 1)),
		makes = list(reagent(REAGENT_ID_BARBECUE, 4))))

/transformation/chem/instant/food/mustard

CAPABILITIES(/transformation/chem/instant/food/mustard)
	configure(transformation(name = REAGENT_MUSTARD, id = REAGENT_ID_MUSTARD,
		takes = list(reagent(REAGENT_ID_MUSTARDPODS, 2), reagent(REAGENT_ID_WATER, 2), reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_HONEY, 1)),
		makes = list(reagent(REAGENT_ID_MUSTARD, 4))))

/transformation/chem/instant/food/vinegar_apple

CAPABILITIES(/transformation/chem/instant/food/vinegar_apple)
	configure(transformation(name = "apple " + REAGENT_VINEGAR, id = "applevinegar",
		takes = list(reagent(REAGENT_ID_APPLEJUICE, 2), reagent(REAGENT_ID_WATER, 2), reagent(REAGENT_ID_SUGAR, 2)),
		catalysts = list(reagent(REAGENT_ID_YEAST, 5)), makes = list(reagent(REAGENT_ID_VINEGAR, 4))))

/transformation/chem/instant/food/vinegar_grape

CAPABILITIES(/transformation/chem/instant/food/vinegar_grape)
	configure(transformation(name = "grape " + REAGENT_VINEGAR, id = "grapevinegar",
		takes = list(reagent(REAGENT_ID_GRAPEJUICE, 2), reagent(REAGENT_ID_WATER, 2), reagent(REAGENT_ID_SUGAR, 2)),
		catalysts = list(reagent(REAGENT_ID_YEAST, 5)), makes = list(reagent(REAGENT_ID_VINEGAR, 4))))

/transformation/chem/instant/food/peanutbutter

CAPABILITIES(/transformation/chem/instant/food/peanutbutter)
	configure(transformation(name = REAGENT_PEANUTBUTTER, id = REAGENT_ID_PEANUTBUTTER,
		takes = list(reagent(REAGENT_ID_PEANUTOIL, 2), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_SODIUMCHLORIDE, 1)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_PEANUTBUTTER, 3))))

/transformation/chem/instant/food/mayonnaise

CAPABILITIES(/transformation/chem/instant/food/mayonnaise)
	configure(transformation(name = REAGENT_MAYO, id = REAGENT_ID_MAYO,
		takes = list(reagent(REAGENT_ID_EGG, 9), reagent(REAGENT_ID_COOKINGOIL, 5), reagent(REAGENT_ID_LEMONJUICE, 5), reagent(REAGENT_ID_SODIUMCHLORIDE, 1)),
		makes = list(reagent(REAGENT_ID_MAYO, 15))))

/transformation/chem/instant/food/cheesewheel

CAPABILITIES(/transformation/chem/instant/food/cheesewheel)
	configure(transformation(name = "Cheesewheel", id = "cheesewheel", takes = list(reagent(REAGENT_ID_MILK, 40)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), made = 1,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/sliceable/cheesewheel, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/meatball

CAPABILITIES(/transformation/chem/instant/food/meatball)
	configure(transformation(name = "Meatball", id = "meatball", takes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_FLOUR, 5)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), made = 3,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/meatball, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/dough

CAPABILITIES(/transformation/chem/instant/food/dough)
	configure(transformation(name = "Dough", id = "dough", takes = list(reagent(REAGENT_ID_EGG, 3), reagent(REAGENT_ID_FLOUR, 10)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_BEER, 1), reagent(REAGENT_ID_SUGAR, 1)), made = 1,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/dough, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/syntiflesh

CAPABILITIES(/transformation/chem/instant/food/syntiflesh)
	configure(transformation(name = "Syntiflesh", id = "syntiflesh", takes = list(reagent(REAGENT_ID_BLOOD, 5), reagent(REAGENT_ID_CLONEXADONE, 1)),
		made = 1, spawns = spawns(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1, per = SPAWN_PER_MADE)))

/*
====================
	Aurora Food
====================
*/

/transformation/chem/instant/food/coating/batter

CAPABILITIES(/transformation/chem/instant/food/coating/batter)
	configure(transformation(name = "Batter", id = REAGENT_ID_BATTER,
		takes = list(reagent(REAGENT_ID_EGG, 3), reagent(REAGENT_ID_FLOUR, 10), reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_SODIUMCHLORIDE, 2)),
		makes = list(reagent(REAGENT_ID_BATTER, 20))))

/transformation/chem/instant/food/coating/beerbatter

CAPABILITIES(/transformation/chem/instant/food/coating/beerbatter)
	configure(transformation(name = "Beer Batter", id = REAGENT_ID_BEERBATTER,
		takes = list(reagent(REAGENT_ID_EGG, 3), reagent(REAGENT_ID_FLOUR, 10), reagent(REAGENT_ID_BEER, 5), reagent(REAGENT_ID_SODIUMCHLORIDE, 2)),
		makes = list(reagent(REAGENT_ID_BEERBATTER, 20))))

/transformation/chem/instant/food/browniemix

CAPABILITIES(/transformation/chem/instant/food/browniemix)
	configure(transformation(name = REAGENT_BROWNIEMIX, id = REAGENT_ID_BROWNIEMIX,
		takes = list(reagent(REAGENT_ID_FLOUR, 5), reagent(REAGENT_ID_COCO, 5), reagent(REAGENT_ID_SUGAR, 5)),
		makes = list(reagent(REAGENT_ID_BROWNIEMIX, 15))))

/transformation/chem/instant/food/cakebatter

CAPABILITIES(/transformation/chem/instant/food/cakebatter)
	configure(transformation(name = REAGENT_CAKEBATTER, id = REAGENT_ID_CAKEBATTER,
		takes = list(reagent(REAGENT_ID_FLOUR, 15), reagent(REAGENT_ID_MILK, 10), reagent(REAGENT_ID_SUGAR, 15), reagent(REAGENT_ID_EGG, 3)),
		makes = list(reagent(REAGENT_ID_CAKEBATTER, 60))))

/transformation/chem/instant/food/butter

CAPABILITIES(/transformation/chem/instant/food/butter)
	configure(transformation(name = "Butter", id = "butter", takes = list(reagent(REAGENT_ID_CREAM, 20), reagent(REAGENT_ID_SODIUMCHLORIDE, 1)),
		made = 1, spawns = spawns(/obj/item/reagent_containers/food/snacks/spreads/butter, 1, per = SPAWN_PER_MADE)))


//////////////////////////////////////////////
////////////////C U B E S////////////////////
////////////////////////////////////////////
/transformation/chem/instant/cube/sagaru

CAPABILITIES(/transformation/chem/instant/cube/sagaru)
	configure(transformation(name = "Saguwu", id = "cubedsagaru",
		takes = list(reagent(REAGENT_ID_CHEESE, 1), reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_CLONEXADONE, 10)), made = 1,
		spawns = spawns(/obj/item/reagent_containers/food/snacks/monkeycube/sarucube, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/food/blondiemix

CAPABILITIES(/transformation/chem/instant/food/blondiemix)
	configure(transformation(name = REAGENT_BLONDIEMIX, id = REAGENT_ID_BLONDIEMIX,
		takes = list(reagent(REAGENT_ID_FLOUR, 5), reagent(REAGENT_ID_VANILLA, 5), reagent(REAGENT_ID_SUGAR, 5)),
		makes = list(reagent(REAGENT_ID_BLONDIEMIX, 15))))

