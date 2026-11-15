// These reactions happen instantaneously, when added to a container that has all other necessary reagents
// They are a subtype of chemical_reaction so that such containers can iterate over only these reactions, and not have to skip other reaction types

/* Common reactions */

/transformation/chem/instant

/transformation/chem/instant/water

CAPABILITIES(/transformation/chem/instant/water)
	configure(transformation(name = REAGENT_WATER, id = REAGENT_ID_WATER, takes = list(reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_HYDROGEN, 2)),
		blocked_by = list(reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_WATER, 1))))

/transformation/chem/instant/thermite

CAPABILITIES(/transformation/chem/instant/thermite)
	configure(transformation(name = REAGENT_THERMITE, id = REAGENT_ID_THERMITE,
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_THERMITE, 3))))

/transformation/chem/instant/pacid

CAPABILITIES(/transformation/chem/instant/pacid)
	configure(transformation(name = REAGENT_PACID, id = REAGENT_ID_PACID,
		takes = list(reagent(REAGENT_ID_NITRATINGMIX, 1), reagent(REAGENT_ID_HYDROCHLORIC, 1)),
		makes = list(reagent(REAGENT_ID_PACID, 3))))

/transformation/chem/instant/virus_food

CAPABILITIES(/transformation/chem/instant/virus_food)
	configure(transformation(name = REAGENT_VIRUSFOOD, id = REAGENT_ID_VIRUSFOOD,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_MILK, 1)), makes = list(reagent(REAGENT_ID_VIRUSFOOD, 5))))

/transformation/chem/instant/stimm

CAPABILITIES(/transformation/chem/instant/stimm)
	configure(transformation(name = REAGENT_STIMM, id = REAGENT_ID_STIMM, takes = list(reagent(REAGENT_ID_LEFT4ZED, 1), reagent(REAGENT_ID_FUEL, 1)),
		catalysts = list(reagent(REAGENT_ID_FUEL, 5)), makes = list(reagent(REAGENT_ID_STIMM, 2))))

/transformation/chem/instant/ironsaline

CAPABILITIES(/transformation/chem/instant/ironsaline)
	configure(transformation(name = REAGENT_IRONSALINE, id = REAGENT_ID_IRONSALINE,
		takes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_WATER, 2)),
		makes = list(reagent(REAGENT_ID_IRONSALINE, 4))))

/transformation/chem/instant/calciumcarbonate

CAPABILITIES(/transformation/chem/instant/calciumcarbonate)
	configure(transformation(name = "Calcium Carbonate", id = REAGENT_ID_CALCIUMCARBONATE,
		takes = list(reagent(REAGENT_ID_OXYGEN, 3), reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_CALCIUMCARBONATE, 2))))

/transformation/chem/instant/carpotoxin

CAPABILITIES(/transformation/chem/instant/carpotoxin)
	configure(transformation(name = REAGENT_CARPOTOXIN, id = REAGENT_ID_CARPOTOXIN,
		takes = list(reagent(REAGENT_ID_SPIDERTOXIN, 2), reagent(REAGENT_ID_BIOMASS, 1), reagent(REAGENT_ID_SIFSAP, 2)),
		catalysts = list(reagent(REAGENT_ID_SIFSAP, 10)), blocked_by = list(reagent(REAGENT_ID_RADIUM, 1)),
		makes = list(reagent(REAGENT_ID_CARPOTOXIN, 2))))

/transformation/chem/instant/lipozine

CAPABILITIES(/transformation/chem/instant/lipozine)
	configure(transformation(name = REAGENT_LIPOZINE, id = REAGENT_ID_LIPOZINE,
		takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_RADIUM, 1)),
		makes = list(reagent(REAGENT_ID_LIPOZINE, 3))))

/transformation/chem/instant/ammonia

CAPABILITIES(/transformation/chem/instant/ammonia)
	configure(transformation(name = REAGENT_AMMONIA, id = REAGENT_ID_AMMONIA,
		takes = list(reagent(REAGENT_ID_HYDROGEN, 3), reagent(REAGENT_ID_NITROGEN, 1)),
		blocked_by = list(reagent(REAGENT_ID_PHORON, 1)), makes = list(reagent(REAGENT_ID_AMMONIA, 3))))

/transformation/chem/instant/diethylamine

CAPABILITIES(/transformation/chem/instant/diethylamine)
	configure(transformation(name = REAGENT_DIETHYLAMINE, id = REAGENT_ID_DIETHYLAMINE,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_ETHANOL, 1)),
		makes = list(reagent(REAGENT_ID_DIETHYLAMINE, 2))))

/transformation/chem/instant/lye

CAPABILITIES(/transformation/chem/instant/lye)
	configure(transformation(name = REAGENT_LYE, id = REAGENT_ID_LYE,
		takes = list(reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		blocked_by = list(reagent(REAGENT_ID_CARBON, 1)), makes = list(reagent(REAGENT_ID_LYE, 3))))

/transformation/chem/instant/left4zed

CAPABILITIES(/transformation/chem/instant/left4zed)
	configure(transformation(name = "Left4Zed", id = REAGENT_ID_LEFT4ZED,
		takes = list(reagent(REAGENT_ID_DIETHYLAMINE, 2), reagent(REAGENT_ID_MUTAGEN, 1)),
		makes = list(reagent(REAGENT_ID_LEFT4ZED, 3))))

/transformation/chem/instant/robustharvest

CAPABILITIES(/transformation/chem/instant/robustharvest)
	configure(transformation(name = "RobustHarvest", id = REAGENT_ID_ROBUSTHARVEST,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_NEUROTOXIC_PROTEIN, 1)),
		makes = list(reagent(REAGENT_ID_ROBUSTHARVEST, 3))))

/transformation/chem/instant/space_cleaner

CAPABILITIES(/transformation/chem/instant/space_cleaner)
	configure(transformation(name = REAGENT_CLEANER, id = REAGENT_ID_CLEANER,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_WATER, 1)), makes = list(reagent(REAGENT_ID_CLEANER, 2))))

/transformation/chem/instant/foaming_agent

CAPABILITIES(/transformation/chem/instant/foaming_agent)
	configure(transformation(name = "Foaming Agent", id = REAGENT_ID_FOAMINGAGENT,
		takes = list(reagent(REAGENT_ID_LITHIUM, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		makes = list(reagent(REAGENT_ID_FOAMINGAGENT, 1))))

/transformation/chem/instant/glycerol

CAPABILITIES(/transformation/chem/instant/glycerol)
	configure(transformation(name = REAGENT_GLYCEROL, id = REAGENT_ID_GLYCEROL,
		takes = list(reagent(REAGENT_ID_CORNOIL, 3), reagent(REAGENT_ID_SACID, 1)), makes = list(reagent(REAGENT_ID_GLYCEROL, 1))))

/transformation/chem/instant/neurotoxin

CAPABILITIES(/transformation/chem/instant/neurotoxin)
	configure(transformation(name = REAGENT_NEUROTOXIN, id = REAGENT_ID_NEUROTOXIN,
		takes = list(reagent(REAGENT_ID_GARGLEBLASTER, 1), reagent(REAGENT_ID_STOXIN, 1)),
		makes = list(reagent(REAGENT_ID_NEUROTOXIN, 2))))

/* Solidification */

/transformation/chem/instant/solidification

CAPABILITIES(/transformation/chem/instant/solidification)
	configure(transformation(name = "Solid Iron", id = "solidiron",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_IRON, REAGENTS_PER_SHEET)), made = 1, spawns = spawns(/obj/item/stack/material/iron, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/phoron

CAPABILITIES(/transformation/chem/instant/solidification/phoron)
	configure(transformation(name = "Solid Phoron", id = "solidphoron",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_PHORON, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/phoron, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/silver

CAPABILITIES(/transformation/chem/instant/solidification/silver)
	configure(transformation(name = "Solid Silver", id = "solidsilver",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_SILVER, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/silver, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/gold

CAPABILITIES(/transformation/chem/instant/solidification/gold)
	configure(transformation(name = "Solid Gold", id = "solidgold",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_GOLD, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/gold, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/platinum

CAPABILITIES(/transformation/chem/instant/solidification/platinum)
	configure(transformation(name = "Solid Platinum", id = "solidplatinum",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_PLATINUM, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/platinum, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/uranium

CAPABILITIES(/transformation/chem/instant/solidification/uranium)
	configure(transformation(name = "Solid Uranium", id = "soliduranium",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_URANIUM, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/uranium, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/hydrogen

CAPABILITIES(/transformation/chem/instant/solidification/hydrogen)
	configure(transformation(name = "Solid Hydrogen", id = "solidhydrogen",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 100), reagent(REAGENT_ID_HYDROGEN, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/mhydrogen, 1, per = SPAWN_STACK_MADE)))

// These are from Xenobio.
/transformation/chem/instant/solidification/steel

CAPABILITIES(/transformation/chem/instant/solidification/steel)
	configure(transformation(name = "Solid Steel", id = "solidsteel",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 10), reagent(REAGENT_ID_IRON, REAGENTS_PER_SHEET), reagent(REAGENT_ID_CARBON, REAGENTS_PER_SHEET)),
		blocked_by = list(reagent(REAGENT_ID_PLATINUM, 1)),
		spawns = spawns(/obj/item/stack/material/steel, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/plasteel

CAPABILITIES(/transformation/chem/instant/solidification/plasteel)
	configure(transformation(name = "Solid Plasteel", id = "solidplasteel",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 10), reagent(REAGENT_ID_IRON, REAGENTS_PER_SHEET), reagent(REAGENT_ID_CARBON, REAGENTS_PER_SHEET), reagent(REAGENT_ID_PLATINUM, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/plasteel, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/plastication

CAPABILITIES(/transformation/chem/instant/plastication)
	configure(transformation(name = "Plastic", id = "solidplastic", takes = list(reagent(REAGENT_ID_PACID, 1), reagent(REAGENT_ID_PLASTICIDE, 2)),
		made = 1, spawns = spawns(/obj/item/stack/material/plastic, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/soapification

CAPABILITIES(/transformation/chem/instant/soapification)
	configure(transformation(name = "Soapification", id = "soapification", takes = list(reagent(REAGENT_ID_COOKINGOIL, 10), reagent(REAGENT_ID_LYE, 2)),
		made = 1, spawns = spawns(/obj/item/soap, 1, per = SPAWN_PER_MADE)))

/transformation/chem/instant/soapification/alt

CAPABILITIES(/transformation/chem/instant/soapification/alt)
	configure(transformation(name = "Soapification2", id = "soapification2", takes = list(reagent(REAGENT_ID_CORNOIL, 10), reagent(REAGENT_ID_LYE, 2))))

/transformation/chem/instant/soapification/gibs // a bit less convinient and grosser, but it makes more potent soap.

CAPABILITIES(/transformation/chem/instant/soapification/gibs)
	configure(transformation(name = "Soapification Gibs", id = "soapificationgibs",
		takes = list(reagent(REAGENT_ID_PROTEIN, 10), reagent(REAGENT_ID_LYE, 10)), made = 1,
		spawns = spawns(/obj/item/soap/homemade, 1, per = SPAWN_PER_MADE)))

/*Carpet Creation*/

/transformation/chem/instant/carpetify

CAPABILITIES(/transformation/chem/instant/carpetify)
	configure(transformation(name = "Carpet", id = "redcarpet", takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		made = 2, spawns = spawns(/obj/item/stack/tile/carpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/bcarpet

CAPABILITIES(/transformation/chem/instant/carpetify/bcarpet)
	configure(transformation(name = "Black Carpet", id = "blackcarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETB, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/bcarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/blucarpet

CAPABILITIES(/transformation/chem/instant/carpetify/blucarpet)
	configure(transformation(name = "Blue Carpet", id = "bluecarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETBLU, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/blucarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/turcarpet

CAPABILITIES(/transformation/chem/instant/carpetify/turcarpet)
	configure(transformation(name = "Turquise Carpet", id = "turcarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETTUR, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/turcarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/sblucarpet

CAPABILITIES(/transformation/chem/instant/carpetify/sblucarpet)
	configure(transformation(name = "Silver Blue Carpet", id = "sblucarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETSBLU, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/sblucarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/clowncarpet

CAPABILITIES(/transformation/chem/instant/carpetify/clowncarpet)
	configure(transformation(name = "Clown Carpet", id = "clowncarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETC, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/gaycarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/pcarpet

CAPABILITIES(/transformation/chem/instant/carpetify/pcarpet)
	configure(transformation(name = "Purple Carpet", id = "purplecarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETP, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/purcarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/carpetify/ocarpet

CAPABILITIES(/transformation/chem/instant/carpetify/ocarpet)
	configure(transformation(name = "Orange Carpet", id = "orangecarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETO, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		spawns = spawns(/obj/item/stack/tile/carpet/oracarpet, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/concrete

CAPABILITIES(/transformation/chem/instant/concrete)
	configure(transformation(name = "Concrete", id = "concretereagent",
		takes = list(reagent(REAGENT_ID_CALCIUM, 2), reagent(REAGENT_ID_SILICATE, 2), reagent(REAGENT_ID_WATER, 2)), made = 1, spawns = spawns(/obj/item/stack/material/concrete, 1, per = SPAWN_STACK_MADE)))

/* Grenade reactions */

/transformation/chem/instant/explosion_potassium

CAPABILITIES(/transformation/chem/instant/explosion_potassium)
	configure(transformation(name = "Explosion", id = "explosion_potassium",
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_POTASSIUM, 1)), made = 2, says = "",
		effects = sets_off(kind = XFORM_FX_EXPLOSION, divisor = 10)))

/transformation/chem/instant/flash_powder

CAPABILITIES(/transformation/chem/instant/flash_powder)
	configure(transformation(name = "Flash powder", id = "flash_powder",
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SULFUR, 1)),
		effects = sets_off(kind = XFORM_FX_WAVE, range = world.view, line_of_sight = TRUE, mob_type = /mob/living/carbon, sparks = 2, flash = TRUE,
			statuses = list(list(3, STAT_WEAKENED, 15), list(5, STAT_STUNNED, 5)))))

/transformation/chem/instant/emp_pulse

CAPABILITIES(/transformation/chem/instant/emp_pulse)
	configure(transformation(name = "EMP Pulse", id = "emp_pulse", takes = list(reagent(REAGENT_ID_URANIUM, 1), reagent(REAGENT_ID_IRON, 1)), made = 2,
		effects = sets_off(kind = XFORM_FX_EMP, divisors = list(24, 20, 18, 14), clears = TRUE)))

/transformation/chem/instant/napalm

CAPABILITIES(/transformation/chem/instant/napalm)
	configure(transformation(name = "Napalm", id = "napalm",
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_SACID, 1)), made = 1,
		effects = sets_off(kind = XFORM_FX_BURN, gases = list(GAS_VOLATILE_FUEL = 1), scale_by_made = TRUE, temperature = 400 + T0C, hotspot = list(700, 400), range = 0, floors_only = TRUE, consumes = "napalm")))

/transformation/chem/instant/chemsmoke

CAPABILITIES(/transformation/chem/instant/chemsmoke)
	configure(transformation(name = "Chemsmoke", id = "chemsmoke",
		takes = list(reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHOSPHORUS, 1)),
		made = 0.4, effects = sets_off(kind = XFORM_FX_SMOKE, clears = TRUE, sfx = SFX_EFFECTS_SMOKE)))

/transformation/chem/instant/foam

CAPABILITIES(/transformation/chem/instant/foam)
	configure(transformation(name = "Foam", id = "foam", takes = list(reagent(REAGENT_ID_FLUOROSURFACTANT, 1), reagent(REAGENT_ID_WATER, 1)), made = 2,
		says = "The solution violently bubbles!", effects = sets_off(kind = XFORM_FX_FOAM, variant = 0, clears = TRUE, tell = "The solution spews out foam!")))

/transformation/chem/instant/metalfoam

CAPABILITIES(/transformation/chem/instant/metalfoam)
	configure(transformation(name = "Metal Foam", id = "metalfoam",
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 3), reagent(REAGENT_ID_FOAMINGAGENT, 1), reagent(REAGENT_ID_PACID, 1)),
		made = 5, effects = sets_off(kind = XFORM_FX_FOAM, variant = 1, tell = "The solution spews out a metalic foam!")))

/transformation/chem/instant/ironfoam

CAPABILITIES(/transformation/chem/instant/ironfoam)
	configure(transformation(name = "Iron Foam", id = "ironlfoam",
		takes = list(reagent(REAGENT_ID_IRON, 3), reagent(REAGENT_ID_FOAMINGAGENT, 1), reagent(REAGENT_ID_PACID, 1)), made = 5,
		effects = sets_off(kind = XFORM_FX_FOAM, variant = 2, tell = "The solution spews out a metalic foam!")))

/* Paint */

/transformation/chem/instant/red_paint

CAPABILITIES(/transformation/chem/instant/red_paint)
	configure(transformation(name = "Red paint", id = "red_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKRED, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#FE191A"))

/transformation/chem/instant/orange_paint

CAPABILITIES(/transformation/chem/instant/orange_paint)
	configure(transformation(name = "Orange paint", id = "orange_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKORANGE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#FFBE4F"))

/transformation/chem/instant/yellow_paint

CAPABILITIES(/transformation/chem/instant/yellow_paint)
	configure(transformation(name = "Yellow paint", id = "yellow_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKYELLOW, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#FDFE7D"))

/transformation/chem/instant/green_paint

CAPABILITIES(/transformation/chem/instant/green_paint)
	configure(transformation(name = "Green paint", id = "green_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKGREEN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#18A31A"))

/transformation/chem/instant/blue_paint

CAPABILITIES(/transformation/chem/instant/blue_paint)
	configure(transformation(name = "Blue paint", id = "blue_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBLUE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#247CFF"))

/transformation/chem/instant/purple_paint

CAPABILITIES(/transformation/chem/instant/purple_paint)
	configure(transformation(name = "Purple paint", id = "purple_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKPURPLE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#CC0099"))

/transformation/chem/instant/grey_paint //mime

CAPABILITIES(/transformation/chem/instant/grey_paint)
	configure(transformation(name = "Grey paint", id = "grey_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKGREY, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#808080"))

/transformation/chem/instant/brown_paint

CAPABILITIES(/transformation/chem/instant/brown_paint)
	configure(transformation(name = "Brown paint", id = "brown_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBROWN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#846F35"))

/transformation/chem/instant/blood_paint

CAPABILITIES(/transformation/chem/instant/blood_paint)
	configure(transformation(name = "Blood paint", id = "blood_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BLOOD, 2)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), data_from = data_from_reagent(REAGENT_ID_BLOOD, "blood_colour", "#FE191A")))

/transformation/chem/instant/milk_paint

CAPABILITIES(/transformation/chem/instant/milk_paint)
	configure(transformation(name = "Milk paint", id = "milk_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MILK, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#F0F8FF"))

/transformation/chem/instant/orange_juice_paint

CAPABILITIES(/transformation/chem/instant/orange_juice_paint)
	configure(transformation(name = "Orange juice paint", id = "orange_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_ORANGEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#E78108"))

/transformation/chem/instant/tomato_juice_paint

CAPABILITIES(/transformation/chem/instant/tomato_juice_paint)
	configure(transformation(name = "Tomato juice paint", id = "tomato_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_TOMATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#731008"))

/transformation/chem/instant/lime_juice_paint

CAPABILITIES(/transformation/chem/instant/lime_juice_paint)
	configure(transformation(name = "Lime juice paint", id = "lime_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LIMEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#365E30"))

/transformation/chem/instant/carrot_juice_paint

CAPABILITIES(/transformation/chem/instant/carrot_juice_paint)
	configure(transformation(name = "Carrot juice paint", id = "carrot_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_CARROTJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#973800"))

/transformation/chem/instant/berry_juice_paint

CAPABILITIES(/transformation/chem/instant/berry_juice_paint)
	configure(transformation(name = "Berry juice paint", id = "berry_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#990066"))

/transformation/chem/instant/grape_juice_paint

CAPABILITIES(/transformation/chem/instant/grape_juice_paint)
	configure(transformation(name = "Grape juice paint", id = "grape_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_GRAPEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#863333"))

/transformation/chem/instant/poisonberry_juice_paint

CAPABILITIES(/transformation/chem/instant/poisonberry_juice_paint)
	configure(transformation(name = "Poison berry juice paint", id = "poisonberry_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POISONBERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#863353"))

/transformation/chem/instant/watermelon_juice_paint

CAPABILITIES(/transformation/chem/instant/watermelon_juice_paint)
	configure(transformation(name = "Watermelon juice paint", id = "watermelon_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_WATERMELONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#B83333"))

/transformation/chem/instant/lemon_juice_paint

CAPABILITIES(/transformation/chem/instant/lemon_juice_paint)
	configure(transformation(name = "Lemon juice paint", id = "lemon_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LEMONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#AFAF00"))

/transformation/chem/instant/banana_juice_paint

CAPABILITIES(/transformation/chem/instant/banana_juice_paint)
	configure(transformation(name = "Banana juice paint", id = "banana_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BANANA, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#C3AF00"))

/transformation/chem/instant/potato_juice_paint

CAPABILITIES(/transformation/chem/instant/potato_juice_paint)
	configure(transformation(name = "Potato juice paint", id = "potato_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POTATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#302000"))

/transformation/chem/instant/carbon_paint

CAPABILITIES(/transformation/chem/instant/carbon_paint)
	configure(transformation(name = "Carbon paint", id = "carbon_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#333333"))

/transformation/chem/instant/aluminum_paint

CAPABILITIES(/transformation/chem/instant/aluminum_paint)
	configure(transformation(name = "Aluminum paint", id = "aluminum_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_ALUMINIUM, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#F0F8FF"))

/*Carpet Recoloring*/
/transformation/chem/instant/carpetdye

CAPABILITIES(/transformation/chem/instant/carpetdye)
	configure(transformation(name = "Black Carpet Dyeing", id = "carpetdyeblack",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETB, 5))))

/transformation/chem/instant/carpetdye/blue

CAPABILITIES(/transformation/chem/instant/carpetdye/blue)
	configure(transformation(name = "Blue Carpet Dyeing", id = "carpetdyeblue",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_FROSTOIL, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETBLU, 5))))

/transformation/chem/instant/carpetdye/tur

CAPABILITIES(/transformation/chem/instant/carpetdye/tur)
	configure(transformation(name = "Turqouise Carpet Dyeing", id = "carpetdyetur",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETTUR, 5))))

/transformation/chem/instant/carpetdye/sblu

CAPABILITIES(/transformation/chem/instant/carpetdye/sblu)
	configure(transformation(name = "Silver Blue Carpet Dyeing", id = "carpetdyesblu",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETSBLU, 5))))

/transformation/chem/instant/carpetdye/clown

CAPABILITIES(/transformation/chem/instant/carpetdye/clown)
	configure(transformation(name = "Clown Carpet Dyeing", id = "carpetdyeclown",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_BANANA, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETC, 5))))

/transformation/chem/instant/carpetdye/purple

CAPABILITIES(/transformation/chem/instant/carpetdye/purple)
	configure(transformation(name = "Purple Carpet Dyeing", id = "carpetdyepurple",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_BERRYJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETP, 5))))

/transformation/chem/instant/carpetdye/orange

CAPABILITIES(/transformation/chem/instant/carpetdye/orange)
	configure(transformation(name = "Orange Carpet Dyeing", id = "carpetdyeorange",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_ORANGEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETO, 5))))

//R-UST Port
/transformation/chem/instant/hydrophoron

CAPABILITIES(/transformation/chem/instant/hydrophoron)
	configure(transformation(name = REAGENT_HYDROPHORON, id = REAGENT_ID_HYDROPHORON,
		takes = list(reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_PHORON, 1)),
		blocked_by = list(reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_COPPER, 1)),
		makes = list(reagent(REAGENT_ID_HYDROPHORON, 2))))

/transformation/chem/instant/deuterium

CAPABILITIES(/transformation/chem/instant/deuterium)
	configure(transformation(name = REAGENT_DEUTERIUM, id = REAGENT_ID_DEUTERIUM,
		takes = list(reagent(REAGENT_ID_HYDROPHORON, 1), reagent(REAGENT_ID_WATER, 2)),
		makes = list(reagent(REAGENT_ID_DEUTERIUM, 3))))

//Skrellian crap.
/transformation/chem/instant/talum_quem

CAPABILITIES(/transformation/chem/instant/talum_quem)
	configure(transformation(name = REAGENT_TALUMQUEM, id = REAGENT_ID_TALUMQUEM,
		takes = list(reagent(REAGENT_ID_BLISS, 2), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_AMATOXIN, 1)),
		makes = list(reagent(REAGENT_ID_TALUMQUEM, 4))))

/transformation/chem/instant/qerr_quem

CAPABILITIES(/transformation/chem/instant/qerr_quem)
	configure(transformation(name = REAGENT_QERRQUEM, id = REAGENT_ID_QERRQUEM,
		takes = list(reagent(REAGENT_ID_NICOTINE, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_SUGAR, 2)),
		makes = list(reagent(REAGENT_ID_QERRQUEM, 4))))

// Biomass, for cloning and bioprinters
/transformation/chem/instant/biomass

CAPABILITIES(/transformation/chem/instant/biomass)
	configure(transformation(name = REAGENT_BIOMASS, id = REAGENT_ID_BIOMASS,
		takes = list(reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_BIOMASS, 6))))

// Neutralization.

/transformation/chem/instant/neutralize_neurotoxic_protein

CAPABILITIES(/transformation/chem/instant/neutralize_neurotoxic_protein)
	configure(transformation(name = "Neutralize Toxic Proteins", id = "neurotoxic_protein_neutral",
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_NEUROTOXIC_PROTEIN, 2)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 2))))

/transformation/chem/instant/neutralize_carpotoxin

CAPABILITIES(/transformation/chem/instant/neutralize_carpotoxin)
	configure(transformation(name = "Neutralize Carpotoxin", id = "carpotoxin_neutral",
		takes = list(reagent(REAGENT_ID_ENZYME, 1), reagent(REAGENT_ID_CARPOTOXIN, 1), reagent(REAGENT_ID_SIFSAP, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 1))))

/transformation/chem/instant/neutralize_spidertoxin

CAPABILITIES(/transformation/chem/instant/neutralize_spidertoxin)
	configure(transformation(name = "Neutralize Spidertoxin", id = "spidertoxin_neutral",
		takes = list(reagent(REAGENT_ID_ENZYME, 1), reagent(REAGENT_ID_SPIDERTOXIN, 1), reagent(REAGENT_ID_SIFSAP, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 1))))

/transformation/chem/instant/artificial_sustenance

CAPABILITIES(/transformation/chem/instant/artificial_sustenance)
	configure(transformation(name = REAGENT_ASUSTENANCE, id = REAGENT_ID_ASUSTENANCE,
		takes = list(reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_MUTAGEN, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_ASUSTENANCE, 1))))

/transformation/chem/instant/titanium_oxidation

CAPABILITIES(/transformation/chem/instant/titanium_oxidation)
	configure(transformation(name = REAGENT_TITANIUMDIOX, id = "oxidize_titanium",
		takes = list(reagent(REAGENT_ID_TITANIUM, 1), reagent(REAGENT_ID_OXYGEN, 2)),
		makes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1))))

/* Metallic paints */
/transformation/chem/instant/metal_paint

CAPABILITIES(/transformation/chem/instant/metal_paint)
	configure(transformation(name = "Metallic white paint", id = "metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINK, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#b2d1da"))

/transformation/chem/instant/red_metal_paint

CAPABILITIES(/transformation/chem/instant/red_metal_paint)
	configure(transformation(name = "Metallic red paint", id = "red_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKRED, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#ff7a7a"))

/transformation/chem/instant/orange_metal_paint

CAPABILITIES(/transformation/chem/instant/orange_metal_paint)
	configure(transformation(name = "Metallic orange paint", id = "orange_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKORANGE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#ffd690"))

/transformation/chem/instant/yellow_metal_paint

CAPABILITIES(/transformation/chem/instant/yellow_metal_paint)
	configure(transformation(name = "Metallic yellow paint", id = "yellow_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKYELLOW, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#ffffab"))

/transformation/chem/instant/green_metal_paint

CAPABILITIES(/transformation/chem/instant/green_metal_paint)
	configure(transformation(name = "Metallic green paint", id = "green_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKGREEN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#69d76b"))

/transformation/chem/instant/blue_metal_paint

CAPABILITIES(/transformation/chem/instant/blue_metal_paint)
	configure(transformation(name = "Metallic blue paint", id = "blue_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBLUE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#81aff5"))

/transformation/chem/instant/purple_metal_paint

CAPABILITIES(/transformation/chem/instant/purple_metal_paint)
	configure(transformation(name = "Metallic purple paint", id = "purple_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKPURPLE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#e77acc"))

/transformation/chem/instant/brown_metal_paint

CAPABILITIES(/transformation/chem/instant/brown_metal_paint)
	configure(transformation(name = "Metallic brown paint", id = "brown_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBROWN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#827655"))

/transformation/chem/instant/orange_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/orange_juice_metal_paint)
	configure(transformation(name = "Metallic orange juice paint", id = "orange_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_ORANGEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#e2a254"))

/transformation/chem/instant/tomato_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/tomato_juice_metal_paint)
	configure(transformation(name = "Metallic tomato juice paint", id = "tomato_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_TOMATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#934e49"))

/transformation/chem/instant/lime_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/lime_juice_metal_paint)
	configure(transformation(name = "Metallic lime juice paint", id = "lime_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LIMEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#556c51"))

/transformation/chem/instant/carrot_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/carrot_juice_metal_paint)
	configure(transformation(name = "Metallic carrot juice paint", id = "carrot_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_CARROTJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#a06a4b"))

/transformation/chem/instant/berry_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/berry_juice_metal_paint)
	configure(transformation(name = "Metallic berry juice paint", id = "berry_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#ae5892"))

/transformation/chem/instant/grape_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/grape_juice_metal_paint)
	configure(transformation(name = "Metallic grape juice paint", id = "grape_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_GRAPEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#925e5e"))

/transformation/chem/instant/poisonberry_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/poisonberry_juice_metal_paint)
	configure(transformation(name = "Metallic poison berry juice paint", id = "poisonberry_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POISONBERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#683c4d"))

/transformation/chem/instant/watermelon_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/watermelon_juice_metal_paint)
	configure(transformation(name = "Metallic watermelon juice paint", id = "watermelon_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_WATERMELONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#a47a7a"))

/transformation/chem/instant/lemon_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/lemon_juice_metal_paint)
	configure(transformation(name = "Metallic lemon juice paint", id = "lemon_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LEMONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#8f8f5c"))

/transformation/chem/instant/banana_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/banana_juice_metal_paint)
	configure(transformation(name = "Metallic banana juice paint", id = "banana_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BANANA, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#9c9129"))

/transformation/chem/instant/potato_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/potato_juice_metal_paint)
	configure(transformation(name = "Metallic potato juice paint", id = "potato_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POTATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#2e2a21"))

/transformation/chem/instant/aphrodisiac

CAPABILITIES(/transformation/chem/instant/aphrodisiac)
	configure(transformation(name = REAGENT_APHRODISIAC, id = REAGENT_ID_APHRODISIAC,
		takes = list(reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_HYDROGEN, 2), reagent(REAGENT_ID_OXYGEN, 2), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_APHRODISIAC, 6))))

// === merged from instant_ch.dm during hard-fork de-suffix (verified no override-order change) ===

/transformation/chem/instant/dyloteane

CAPABILITIES(/transformation/chem/instant/dyloteane)
	configure(transformation(name = REAGENT_DYLOTEANE, id = REAGENT_ID_DYLOTEANE,
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_TEA, 1)), makes = list(reagent(REAGENT_ID_DYLOTEANE, 1))))

/transformation/chem/instant/dyloteane/super

CAPABILITIES(/transformation/chem/instant/dyloteane/super)
	configure(transformation(name = "dyloteanesuper", id = "dyloteanesuper",
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_TEA, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_DYLOTEANE, 10))))

/transformation/chem/instant/peridaxon_ch

CAPABILITIES(/transformation/chem/instant/peridaxon_ch)
	configure(transformation(name = REAGENT_PERIDAXON, id = "peridaxon_ch",
		takes = list(reagent(REAGENT_ID_CORDRADAXON, 1), reagent(REAGENT_ID_GASTIRODAXON, 1), reagent(REAGENT_ID_HEPANEPHRODAXON, 1), reagent(REAGENT_ID_RESPIRODAXON, 1)),
		makes = list(reagent(REAGENT_ID_PERIDAXON, 12))))

/transformation/chem/instant/sorbitol

CAPABILITIES(/transformation/chem/instant/sorbitol)
	configure(transformation(name = REAGENT_SORBITOL, id = REAGENT_ID_SORBITOL,
		takes = list(reagent(REAGENT_ID_UNSORBITOL, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_SORBITOL, 2))))

/transformation/chem/instant/glucose

CAPABILITIES(/transformation/chem/instant/glucose)
	configure(transformation(name = REAGENT_GLUCOSE, id = REAGENT_ID_GLUCOSE,
		takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_GLUCOSE, 1))))
///SAP RECIPES//////

/transformation/chem/instant/myelamine_sap //This is the clotting agent used by clotting packs.

CAPABILITIES(/transformation/chem/instant/myelamine_sap)
	configure(transformation(name = REAGENT_MYELAMINE, id = REAGENT_ID_MYELAMINE + "sap",
		takes = list(reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_IRON, 2), reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_BLUESAP, 1)),
		makes = list(reagent(REAGENT_ID_MYELAMINE, 1))))

/transformation/chem/instant/nutrient

CAPABILITIES(/transformation/chem/instant/nutrient)
	configure(transformation(name = REAGENT_NUTRIMENT, id = REAGENT_ID_NUTRIMENT,
		takes = list(reagent(REAGENT_PURPLESAP, 1), reagent(REAGENT_ID_ORANGESAP, 1), reagent(REAGENT_ID_BLUESAP, 1)),
		catalysts = list(reagent(REAGENT_ID_WATER, 5)), makes = list(reagent(REAGENT_ID_NUTRIMENT, 3))))

// Frost oil reactions for material sheets
/transformation/chem/instant/solidification/aluminium

CAPABILITIES(/transformation/chem/instant/solidification/aluminium)
	configure(transformation(name = "Solid Aluminium", id = "solidaluminium",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_ALUMINIUM, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/aluminium, 1, per = SPAWN_STACK_MADE)))

/transformation/chem/instant/solidification/copper

CAPABILITIES(/transformation/chem/instant/solidification/copper)
	configure(transformation(name = "Solid Copper", id = "solidcopper",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_COPPER, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/copper, 1, per = SPAWN_STACK_MADE)))

//YW stuff

/transformation/chem/instant/phenethylamine

CAPABILITIES(/transformation/chem/instant/phenethylamine)
	configure(transformation(name = REAGENT_PHENETHYLAMINE, id = REAGENT_ID_PHENETHYLAMINE,
		takes = list(reagent(REAGENT_ID_PAROXETINE, 1), reagent(REAGENT_ID_BENZILATE, 1)),
		makes = list(reagent(REAGENT_ID_PHENETHYLAMINE, 2))))

// Xenochem stuff
/transformation/chem/instant/xenolazarus // Moved here because upstream axed it and this file cannot conflict

CAPABILITIES(/transformation/chem/instant/xenolazarus)
	configure(transformation(name = "Discount Lazarus", id = "discountlazarus",
		takes = list(reagent(REAGENT_ID_MONSTERTAMER, 5), reagent(REAGENT_ID_CLONEXADONE, 5)),
		notice = /datum/notice/transformed/xenolazarus))

/// Discount Lazarus settled in a body: a xenochimera's state answers it (xenochimera/lazarus_reacted()).
/datum/notice/transformed/xenolazarus

// === merged from instant_vr.dm during hard-fork de-suffix (verified no override-order change) ===
///////////////////////////////////////////////////////////////////////////////////
/// Micro/Macro chemicals

/transformation/chem/instant/dontcrossthebeams

CAPABILITIES(/transformation/chem/instant/dontcrossthebeams)
	configure(transformation(name = "Don't Cross The Beams", id = "dontcrossthebeams",
		takes = list(reagent(REAGENT_ID_MICROCILLIN, 1), reagent(REAGENT_ID_MACROCILLIN, 1)),
		effects = sets_off(kind = XFORM_FX_GRAVITY, direction = GRAVITY_PULL, range = 3, pulses = 3, sfx = SFX_WEAPONS_GAUSS_SHOOT, empties = TRUE)))

///////////////////////////////////////////////////////////////////////////////////
/// TF chemicals
/transformation/chem/instant/androrovir_bootleg

CAPABILITIES(/transformation/chem/instant/androrovir_bootleg)
	configure(transformation(name = "Bootleg Androrovir", id = "androrovir_bootleg",
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_PROTEIN, 10), reagent(REAGENT_ID_CAPSAICIN, 10)),
		makes = list(reagent(REAGENT_ID_ANDROROVIR, 1))))

/transformation/chem/instant/gynorovir_bootleg

CAPABILITIES(/transformation/chem/instant/gynorovir_bootleg)
	configure(transformation(name = "Bootleg Gynorovir", id = "gynorovir_bootleg",
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_SOYMILK, 10), reagent(REAGENT_ID_SUGAR, 10)),
		makes = list(reagent(REAGENT_ID_GYNOROVIR, 1))))

/transformation/chem/instant/androgynorovir_bootleg

CAPABILITIES(/transformation/chem/instant/androgynorovir_bootleg)
	configure(transformation(name = "Bootleg Androgynorovir", id = "androgynorovir_bootleg",
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_COLA, 10), reagent(REAGENT_ID_BERRYJUICE, 10)),
		makes = list(reagent(REAGENT_ID_ANDROGYNOROVIR, 1))))

///////////////////////////////////////////////////////////////////////////////////
/// Miscellaneous Reactions

/transformation/chem/instant/foam/softdrink

CAPABILITIES(/transformation/chem/instant/foam/softdrink)
	configure(transformation(name = "Decarbonated Drink", id = "soda_fizz", takes = list(reagent(REAGENT_ID_COLA, 1), reagent(REAGENT_ID_MINT, 1))))

/transformation/chem/instant/firefightingfoam //TODO: Make it so we can add this to the foam tanks to refill them

CAPABILITIES(/transformation/chem/instant/firefightingfoam)
	configure(transformation(name = REAGENT_FIREFOAM, id = "firefighting foam", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_FLUORINE, 10)), makes = list(reagent(REAGENT_ID_FIREFOAM, 1))))

/transformation/chem/instant/firefightingfoamqol //Please don't abuse this and make us remove it. Seriously.

CAPABILITIES(/transformation/chem/instant/firefightingfoamqol)
	configure(transformation(name = "Firefighting Foam EZ", id = "firefighting foam ez", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_FIREFOAM, 5)), blocked_by = list(reagent(REAGENT_ID_FLUORINE, 0.01)),
		makes = list(reagent(REAGENT_ID_FIREFOAM, 1))))

///////////////////////////////////////////////////////////////////////////////////
/// Vore Drugs

/transformation/chem/instant/ickypak

CAPABILITIES(/transformation/chem/instant/ickypak)
	configure(transformation(name = REAGENT_ICKYPAK, id = REAGENT_ID_ICKYPAK,
		takes = list(reagent(REAGENT_ID_HYPERZINE, 4), reagent(REAGENT_ID_FLUOROSURFACTANT, 1)),
		makes = list(reagent(REAGENT_ID_ICKYPAK, 5))))

/transformation/chem/instant/unsorbitol

CAPABILITIES(/transformation/chem/instant/unsorbitol)
	configure(transformation(name = REAGENT_UNSORBITOL, id = REAGENT_ID_UNSORBITOL,
		takes = list(reagent(REAGENT_ID_MUTAGEN, 3), reagent(REAGENT_ID_LIPOZINE, 2)),
		makes = list(reagent(REAGENT_ID_UNSORBITOL, 5))))

///////////////////////////////////////////////////////////////////////////////////
/// Other Drugs
///////////////////////////////////////////////////////////////////////////////////
/// Reagent colonies.
/transformation/chem/instant/meatcolony

CAPABILITIES(/transformation/chem/instant/meatcolony)
	configure(transformation(name = REAGENT_ID_PROTEIN, id = REAGENT_ID_MEATCOLONY,
		takes = list(reagent(REAGENT_ID_MEATCOLONY, 5), reagent(REAGENT_ID_VIRUSFOOD, 5)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 60))))

/transformation/chem/instant/plantcolony

CAPABILITIES(/transformation/chem/instant/plantcolony)
	configure(transformation(name = REAGENT_ID_NUTRIMENT, id = REAGENT_ID_PLANTCOLONY,
		takes = list(reagent(REAGENT_ID_PLANTCOLONY, 5), reagent(REAGENT_ID_VIRUSFOOD, 5)),
		makes = list(reagent(REAGENT_ID_NUTRIMENT, 60))))

///////////////////////////////////////////////////////////////////////////////////
/// Upstream Adjustments
///////////////////////////////
//SLIME-RELATED BELOW HERE///////
///////////////////////////////

// === merged from instant_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
//Chemist update

//Xenobotany update

//Some extra metal solidification reactions
/transformation/chem/instant/solidification/deuterium

CAPABILITIES(/transformation/chem/instant/solidification/deuterium)
	configure(transformation(name = "Solid Deuterium", id = "soliddeuterium",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_DEUTERIUM, REAGENTS_PER_SHEET)),
		spawns = spawns(/obj/item/stack/material/deuterium, 1, per = SPAWN_STACK_MADE)))

//Injectable toxin reactions
/transformation/chem/instant/succubi_paralize

CAPABILITIES(/transformation/chem/instant/succubi_paralize)
	configure(transformation(name = "paralyzingfluid", id = "paralyzingfluid",
		takes = list(reagent(REAGENT_ID_BENZILATE, 1), reagent(REAGENT_ID_CRYPTOBIOLIN, 1)),
		makes = list(reagent("succubi_paralize", 2))))

/transformation/chem/instant/numbingenzyme

CAPABILITIES(/transformation/chem/instant/numbingenzyme)
	configure(transformation(name = "numbingenzyme", id = "numbingenzyme",
		takes = list(reagent(REAGENT_ID_TRAMADOL, 1), reagent(REAGENT_ID_PROTEIN, 2), reagent(REAGENT_ID_ADRANOL, 1)),
		makes = list(reagent(REAGENT_ID_NUMBENZYME, 4))))
