/datum/supply_pack/chemistry_dispenser
	name = "Reagent dispenser"
	contains = list(
			/obj/machinery/chemical_dispenser{anchored = FALSE}
		)
	cost = 25
	containertype = /obj/structure/largecrate
	containername = "reagent dispenser crate"
	group = "Reagents"

/datum/supply_pack/beer_dispenser
	name = "Booze dispenser"
	contains = list(
			/obj/machinery/chemical_dispenser/bar_alc{anchored = FALSE}
		)
	cost = 25
	containertype = /obj/structure/largecrate
	containername = "booze dispenser crate"
	group = "Reagents"

/datum/supply_pack/soda_dispenser
	name = "Soda dispenser"
	contains = list(
			/obj/machinery/chemical_dispenser/bar_soft{anchored = FALSE}
		)
	cost = 25
	containertype = /obj/structure/largecrate
	containername = "soda dispenser crate"
	group = "Reagents"

/datum/supply_pack/coffee_dispenser
	name = "Coffee dispenser"
	contains = list(
			/obj/machinery/chemical_dispenser/bar_coffee{anchored = FALSE}
		)
	cost = 25
	containertype = /obj/structure/largecrate
	containername = "coffee dispenser crate"
	group = "Reagents"

/datum/supply_pack/syrup_dispenser
	name = "Syrup dispenser"
	contains = list(
			/obj/machinery/chemical_dispenser/bar_syrup{anchored = FALSE}
		)
	cost = 25
	containertype = /obj/structure/largecrate
	containername = "Syrup dispenser crate"
	group = "Reagents"

/datum/supply_pack/reagents
	name = "Chemistry dispenser refill"
	contains = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hydrogen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lithium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/carbon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/nitrogen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/oxygen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/fluorine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/aluminum),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/silicon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/phosphorus),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sulfur),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/chlorine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/potassium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/iron),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/copper),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mercury),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/radium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ethanol),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sacid),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tungsten),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/calcium)
		)
	cost = 150
	containertype = /obj/structure/closet/crate/secure
	containername = "chemical crate"
	access = list(ACCESS_CHEMISTRY)
	group = "Reagents"

/datum/supply_pack/alcohol_reagents
	name = "Bar alcoholic dispenser refill"
	contains = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon_lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodawater),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tonic),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/beer),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/kahlua),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/whiskey),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/redwine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/whitewine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/vodka),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/gin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/rum),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tequila),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/vermouth),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cognac),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cider),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ale),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mead),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/bitters)
		)
	cost = 50
	containertype = /obj/structure/closet/crate/secure
	containername = "alcoholic drinks crate"
	access = list(ACCESS_BAR)
	group = "Reagents"

/datum/supply_pack/softdrink_reagents
	name = "Bar soft drink dispenser refill"
	contains = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ice),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/coffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cream),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/icetea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cola),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/smw),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dr_gibb),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/spaceup),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tonic),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodawater),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon_lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/watermelon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/grapesoda),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/pineapple)
		)
	cost = 50
	containertype = /obj/structure/closet/crate
	containername = "soft drinks crate"
	group = "Reagents"

/datum/supply_pack/coffee_reagents
	name = "Coffee machine dispenser refill"
	contains = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/coffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/drip_coffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cafe_latte),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/soy_latte),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hot_coco),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/milk),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cream),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/milk_foam),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ice),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mint),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/berry),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/greentea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/decaf),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/chaitea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/decafchai)
		)
	cost = 50
	containertype = /obj/structure/closet/crate
	containername = "coffee drinks crate"
	group = "Reagents"

/datum/supply_pack/syrup_reagents
	name = "Syrup machine dispenser refill"
	contains = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_pumpkin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_caramel),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_scaramel),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_irish),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_almond),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_cinnamon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_pistachio),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_vanilla),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_toffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_cherry),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/grenadine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_butterscotch),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_chocolate),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_wchocolate),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_strawberry),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_coconut),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_ginger),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_gingerbread),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_peppermint),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_birthday)
		)
	cost = 50
	containertype = /obj/structure/closet/crate
	containername = "Syrup crate"
	group = "Reagents"

/datum/supply_pack/dispenser_cartridges
	name = "Empty dispenser cartridges"
	contains = list(
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge,
			/obj/item/reagent_containers/chem_disp_cartridge
		)
	cost = 15
	containertype = /obj/structure/closet/crate
	containername = "dispenser cartridge crate"
	group = "Reagents"

#define SEC_PACK(_tname, _type, _name, _cname, _cost, _access)\
	/datum/supply_pack/dispenser_cartridges/##_tname {\
		name = _name ;\
		containername = _cname ;\
		containertype = /obj/structure/closet/crate/secure;\
		access = list( _access );\
		cost = _cost ;\
		contains = list( _type , _type );\
		group = "Reagent Cartridges"\
	}
#define PACK(_tname, _type, _name, _cname, _cost)\
	/datum/supply_pack/dispenser_cartridges/##_tname {\
		name = _name ;\
		containername = _cname ;\
		containertype = /obj/structure/closet/crate;\
		cost = _cost ;\
		contains = list( _type , _type );\
		group = "Reagent Cartridges"\
	}

// Chemistry-restricted (raw reagents excluding sugar/water)
//      Datum path  Contents type                                                       Supply pack name                  Container name                         Cost  Container access
SEC_PACK(hydrogen,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hydrogen),   "Reagent refill - Hydrogen",      "hydrogen reagent cartridge crate",      15, ACCESS_CHEMISTRY)
SEC_PACK(lithium,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lithium),    "Reagent refill - Lithium",       "lithium reagent cartridge crate",       15, ACCESS_CHEMISTRY)
SEC_PACK(carbon,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/carbon),     "Reagent refill - Carbon",        "carbon reagent cartridge crate",        15, ACCESS_CHEMISTRY)
SEC_PACK(nitrogen,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/nitrogen),   "Reagent refill - Nitrogen",      "nitrogen reagent cartridge crate",      15, ACCESS_CHEMISTRY)
SEC_PACK(oxygen,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/oxygen),     "Reagent refill - Oxygen",        "oxygen reagent cartridge crate",        15, ACCESS_CHEMISTRY)
SEC_PACK(fluorine,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/fluorine),   "Reagent refill - Fluorine",      "fluorine reagent cartridge crate",      15, ACCESS_CHEMISTRY)
SEC_PACK(sodium,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodium),     "Reagent refill - Sodium",        "sodium reagent cartridge crate",        15, ACCESS_CHEMISTRY)
SEC_PACK(aluminium, VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/aluminum),   "Reagent refill - Aluminum",      "aluminum reagent cartridge crate",      15, ACCESS_CHEMISTRY)
SEC_PACK(silicon,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/silicon),    "Reagent refill - Silicon",       "silicon reagent cartridge crate",       15, ACCESS_CHEMISTRY)
SEC_PACK(phosphorus,VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/phosphorus), "Reagent refill - Phosphorus",    "phosphorus reagent cartridge crate",    15, ACCESS_CHEMISTRY)
SEC_PACK(sulfur,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sulfur),     "Reagent refill - Sulfur",        "sulfur reagent cartridge crate",        15, ACCESS_CHEMISTRY)
SEC_PACK(chlorine,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/chlorine),   "Reagent refill - Chlorine",      "chlorine reagent cartridge crate",      15, ACCESS_CHEMISTRY)
SEC_PACK(potassium, VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/potassium),  "Reagent refill - Potassium",     "potassium reagent cartridge crate",     15, ACCESS_CHEMISTRY)
SEC_PACK(iron,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/iron),       "Reagent refill - Iron",          "iron reagent cartridge crate",          15, ACCESS_CHEMISTRY)
SEC_PACK(copper,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/copper),     "Reagent refill - Copper",        "copper reagent cartridge crate",        15, ACCESS_CHEMISTRY)
SEC_PACK(mercury,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mercury),    "Reagent refill - Mercury",       "mercury reagent cartridge crate",       15, ACCESS_CHEMISTRY)
SEC_PACK(radium,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/radium),     "Reagent refill - Radium",        "radium reagent cartridge crate",        15, ACCESS_CHEMISTRY)
SEC_PACK(ethanol,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ethanol),    "Reagent refill - Ethanol",       "ethanol reagent cartridge crate",       15, ACCESS_CHEMISTRY)
SEC_PACK(sacid,     VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sacid),      "Reagent refill - Sulfuric Acid", "sulfuric acid reagent cartridge crate", 15, ACCESS_CHEMISTRY)
SEC_PACK(tungsten,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tungsten),   "Reagent refill - Tungsten",      "tungsten reagent cartridge crate",      15, ACCESS_CHEMISTRY)
SEC_PACK(calcium,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/calcium),    "Reagent refill - Calcium",       "calcium reagent cartridge crate",       15, ACCESS_CHEMISTRY)

// Bar-restricted (alcoholic drinks)
//      Datum path Contents type                                                      Supply pack name                Container name                      Cost  Container access
SEC_PACK(beer,     VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/beer),      "Reagent refill - Beer",        "beer reagent cartridge crate",       15, ACCESS_BAR)
SEC_PACK(kahlua,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/kahlua),    "Reagent refill - Kahlua",      "kahlua reagent cartridge crate",     15, ACCESS_BAR)
SEC_PACK(whiskey,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/whiskey),   "Reagent refill - Whiskey",     "whiskey reagent cartridge crate",    15, ACCESS_BAR)
SEC_PACK(rwine,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/redwine),   "Reagent refill - Red Wine",    "red wine reagent cartridge crate",   15, ACCESS_BAR)
SEC_PACK(wwine,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/whitewine), "Reagent refill - White Wine",  "white wine reagent cartridge crate", 15, ACCESS_BAR)
SEC_PACK(vodka,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/vodka),     "Reagent refill - Vodka",       "vodka reagent cartridge crate",      15, ACCESS_BAR)
SEC_PACK(gin,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/gin),       "Reagent refill - Gin",         "gin reagent cartridge crate",        15, ACCESS_BAR)
SEC_PACK(rum,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/rum),       "Reagent refill - Rum",         "rum reagent cartridge crate",        15, ACCESS_BAR)
SEC_PACK(tequila,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tequila),   "Reagent refill - Tequila",     "tequila reagent cartridge crate",    15, ACCESS_BAR)
SEC_PACK(vermouth, VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/vermouth),  "Reagent refill - Vermouth",    "vermouth reagent cartridge crate",   15, ACCESS_BAR)
SEC_PACK(cognac,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cognac),    "Reagent refill - Cognac",      "cognac reagent cartridge crate",     15, ACCESS_BAR)
SEC_PACK(ale,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ale),       "Reagent refill - Ale",         "ale reagent cartridge crate",        15, ACCESS_BAR)
SEC_PACK(mead,     VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mead),      "Reagent refill - Mead",        "mead reagent cartridge crate",       15, ACCESS_BAR)

// Unrestricted (water, sugar, non-alcoholic drinks)
//  Datum path   Contents type                                                       Supply pack name                        Container name                                          Cost
PACK(water,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),      "Reagent refill - Water",               "water reagent cartridge crate",                         15)
PACK(sugar,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),      "Reagent refill - Sugar",               "sugar reagent cartridge crate",                         15)
PACK(ice,        VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ice),        "Reagent refill - Ice",                 "ice reagent cartridge crate",                           15)
PACK(tea,        VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tea),        "Reagent refill - Tea",                 "tea reagent cartridge crate",                           15)
PACK(icetea,     VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/icetea),     "Reagent refill - Iced Tea",            "iced tea reagent cartridge crate",                      15)
PACK(cola,       VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cola),       "Reagent refill - Space Cola",          "\improper Space Cola reagent cartridge crate",          15)
PACK(smw,        VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/smw),        "Reagent refill - Space Mountain Wind", "\improper Space Mountain Wind reagent cartridge crate", 15)
PACK(dr_gibb,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dr_gibb),    "Reagent refill - Dr. Gibb",            "\improper Dr. Gibb reagent cartridge crate",            15)
PACK(spaceup,    VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/spaceup),    "Reagent refill - Space-Up",            "\improper Space-Up reagent cartridge crate",            15)
PACK(tonic,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tonic),      "Reagent refill - Tonic Water",         "tonic water reagent cartridge crate",                   15)
PACK(sodawater,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodawater),  "Reagent refill - Soda Water",          "soda water reagent cartridge crate",                    15)
PACK(lemon_lime, VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon_lime), "Reagent refill - Lemon-Lime Juice",    "lemon-lime juice reagent cartridge crate",              15)
PACK(orange,     VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),     "Reagent refill - Orange Juice",        "orange juice reagent cartridge crate",                  15)
PACK(lime,       VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),       "Reagent refill - Lime Juice",          "lime juice reagent cartridge crate",                    15)
PACK(lemon,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon),      "Reagent refill - Lemon Juice",         "lemon juice reagent cartridge crate",                   15)
PACK(watermelon, VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/watermelon), "Reagent refill - Watermelon Juice",    "watermelon juice reagent cartridge crate",              15)
PACK(coffee,     VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/coffee),     "Reagent refill - Coffee",              "coffee reagent cartridge crate",                        15)
PACK(cafe_latte, VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cafe_latte), "Reagent refill - Cafe Latte",          "cafe latte reagent cartridge crate",                    15)
PACK(soy_latte,  VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/soy_latte),  "Reagent refill - Soy Latte",           "soy latte reagent cartridge crate",                     15)
PACK(hot_coco,   VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hot_coco),   "Reagent refill - Hot Coco",            "hot coco reagent cartridge crate",                      15)
PACK(milk,       VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/milk),       "Reagent refill - Milk",                "milk reagent cartridge crate",                          15)
PACK(cream,      VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cream),      "Reagent refill - Cream",               "cream reagent cartridge crate",                         15)

#undef SEC_PACK
#undef PACK
