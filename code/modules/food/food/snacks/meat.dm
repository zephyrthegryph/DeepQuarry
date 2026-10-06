/obj/item/reagent_containers/food/snacks/meat
	bitesize = 1.5
	name = "meat"
	desc = "A slab of meat."
	icon_state = "meat"
	filling_color = "#FF1C1C"
	center_of_mass_x = 16
	center_of_mass_y = 14



/obj/item/reagent_containers/food/snacks/meat/cook()

	if (!isnull(cooked_icon))
		icon_state = cooked_icon
		flat_icon = null //Force regenating the flat icon for coatings, since we've changed the icon of the thing being coated
	..()

	if (name == initial(name))
		name = "cooked [name]"

CAPABILITIES(/obj/item/reagent_containers/food/snacks/meat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_TRIGLYCERIDE = 2)))
	op("cut_strips", item(/obj/item/material/knife), priority(OP_PRIORITY_PART + 1), label("Cut it into strips"), then(PROC_REF(cut_into_strips)))

/obj/item/reagent_containers/food/snacks/meat/proc/cut_into_strips(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/rawcutlet, "You cut the meat into thin strips.", copies = 3)

/obj/item/reagent_containers/food/snacks/meat/syntiflesh
	name = "synthetic meat"
	desc = "A synthetic slab of flesh."

// Seperate definitions because some food likes to know if it's human.
// TODO: rewrite kitchen code to check a var on the meat item so we can remove
// all these sybtypes.
/obj/item/reagent_containers/food/snacks/meat/human
/obj/item/reagent_containers/food/snacks/meat/monkey
	//same as plain meat

/obj/item/reagent_containers/food/snacks/meat/corgi
	name = "dogmeat"
	desc = "Tastes like... well, you know."

/obj/item/reagent_containers/food/snacks/meat/chicken
	name = "poultry"
	icon_state = "chickenbreast"
	cooked_icon = "chickensteak"
	filling_color = "#BBBBAA"

/obj/item/reagent_containers/food/snacks/meat/chicken/Initialize(mapload)
	. = ..()
	reagents.remove_reagent(REAGENT_ID_TRIGLYCERIDE, INFINITY)
	//Chicken is low fat. Less total calories than other meats

/obj/item/reagent_containers/food/snacks/crabmeat
	name = "crustacean legs"
	desc = "... Coffee? Is that you?"
	icon_state = "crabmeat"
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/crabmeat)
	configure(reagents(add = list(REAGENT_ID_SEAFOOD = 2)))

/obj/item/reagent_containers/food/snacks/hugemushroomslice
	name = "fungus slice"
	desc = "A slice from a huge mushroom."
	icon_state = "hugemushroomslice"
	filling_color = "#E0D7C5"
	center_of_mass_x = 17
	center_of_mass_y = 16
	nutriment_amt = 3
	nutriment_desc = list("raw" = 2, PLANT_MUSHROOMS = 2)
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/hugemushroomslice)
	configure(reagents(add = list(REAGENT_ID_PSILOCYBIN = 3, REAGENT_ID_FUNGI = 1)))

/obj/item/reagent_containers/food/snacks/tomatomeat
	name = "tomato slice"
	desc = "A slice from a huge tomato"
	icon_state = "tomatomeat"
	filling_color = "#DB0000"
	center_of_mass_x = 17
	center_of_mass_y = 16
	nutriment_amt = 3
	nutriment_desc = list("raw" = 2, PLANT_TOMATO = 3)
	bitesize = 6

/obj/item/reagent_containers/food/snacks/bearmeat
	name = "bearmeat"
	desc = "A very manly slab of meat."
	icon_state = "bearmeat"
	filling_color = "#DB0000"
	center_of_mass_x = 16
	center_of_mass_y = 10
	bitesize = 3

CAPABILITIES(/obj/item/reagent_containers/food/snacks/bearmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 24, REAGENT_ID_HYPERZINE = 10)))

/obj/item/reagent_containers/food/snacks/xenomeat
	name = "xenomeat"
	desc = "A slab of green meat. Smells like acid."
	icon_state = "xenomeat"
	filling_color = "#43DE18"
	center_of_mass_x = 16
	center_of_mass_y = 10
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/xenomeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 12, REAGENT_ID_PACID = 12)))

/obj/item/reagent_containers/food/snacks/xenomeat/spidermeat // Substitute for recipes requiring xeno meat.
	name = "insect meat"
	desc = "A slab of green meat."
	icon_state = "xenomeat"
	filling_color = "#43DE18"
	center_of_mass_x = 16
	center_of_mass_y = 10
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/xenomeat/spidermeat)
	configure(reagents(add = list(REAGENT_ID_SPIDERTOXIN = 12)))

/obj/item/reagent_containers/food/snacks/xenomeat/spidermeat/Initialize(mapload)
	. = ..()
	reagents.remove_reagent(REAGENT_ID_PACID,6)

/obj/item/reagent_containers/food/snacks/rawturkey
	name = "raw turkey"
	desc = "Naked and hollow."
	icon_state = "rawturkey"
	bitesize = 2.5

CAPABILITIES(/obj/item/reagent_containers/food/snacks/rawturkey)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 10)))

/obj/item/reagent_containers/food/snacks/meat/fox
	name = "foxmeat"
	desc = "The fox doesn't say a goddamn thing, now."

/obj/item/reagent_containers/food/snacks/meat/grubmeat
	bitesize = 6
	name = "grubmeat"
	desc = "A slab of grub meat, it gives a gentle shock if you touch it"
	icon = 'icons/obj/food.dmi'
	icon_state = "grubmeat"
	center_of_mass_x = 16
	center_of_mass_y = 10

CAPABILITIES(/obj/item/reagent_containers/food/snacks/meat/grubmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 1, REAGENT_ID_SHOCKCHEM = 6)))


GLOBAL_LIST_INIT(worm_meat_spawns, list (
		/obj/random/junk = 30,
		/obj/random/trash = 30,
		/obj/random/maintenance/clean = 15,
		/obj/random/tool = 15,
		/obj/random/medical = 3,
		/obj/random/bomb_supply = 7,
		/obj/random/contraband = 3,
		/obj/random/unidentified_medicine/old_medicine = 7,
		/obj/item/strangerock = 3,
		/obj/item/ore/phoron = 7,
		/obj/random/handgun = 1,
		/obj/random/toolbox = 4,
		/obj/random/drinkbottle = 5
))

/obj/item/reagent_containers/food/snacks/meat/worm
	bitesize = 3
	name = "weird meat"
	desc = "A chunk of pulsating meat."
	icon_state = "wormmeat"
	filling_color = "#551A8B"
	center_of_mass_x = 16
	center_of_mass_y = 14



// A knife on it also frees what is inside, and then cuts it as any meat is cut.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/meat/worm)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_PHORON = 3, REAGENT_ID_MYELAMINE = 3)))
	op("free_chunks", item(/obj/item/material/knife), priority(OP_PRIORITY_PART + 2), label("Cut the tissue"), then(PROC_REF(chunks_freed)), passes())

/obj/item/reagent_containers/food/snacks/meat/worm/proc/chunks_freed(datum/act/op/A)
	var/mob/user = A.actor
	var/to_spawn = pickweight(GLOB.worm_meat_spawns)
	new to_spawn(get_turf(src))
	if(prob(20))
		user.visible_message(span_alien("Something oozes out of \the [src] as it is cut."))
	to_chat(user, span_alien("You cut the tissue holding the chunks together."))
	return OP_OK

/obj/item/reagent_containers/food/snacks/deathclawmeat
	name = "Death claw Meat"
	desc = "A slice from a deathclaw"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_DEATHBLOOD = 6)
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/deathclawmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_DEATHBLOOD = 6)))

/obj/item/reagent_containers/food/snacks/dragonmeat
	name = "Dragon Meat"
	desc = "A slice from a mighty dragon"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_LIQUIDFIRE = 6)
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/dragonmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_LIQUIDFIRE = 6)))

/obj/item/reagent_containers/food/snacks/phorondragonmeat
	name = "Phoron Dragon Meat"
	desc = "A slice from a mighty dragon"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_NEOLIQUIDFIRE = 6, REAGENT_ID_PHORON = 3)
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/phorondragonmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 6, REAGENT_ID_NEOLIQUIDFIRE = 6, REAGENT_ID_PHORON = 3)))

/obj/item/reagent_containers/food/snacks/metroidmeat
	name = "Metroid Slice"
	desc = "A slice from a metroid"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 3, REAGENT_ID_LIQUIDLIFE = 3)
	bitesize = 6

CAPABILITIES(/obj/item/reagent_containers/food/snacks/metroidmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 3, REAGENT_ID_LIQUIDLIFE = 3)))

/obj/item/reagent_containers/food/snacks/meat/raymeat
	name = "Solar Ray Meat"
	desc = "You aren't sure how ediable this is"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 3, REAGENT_ID_CAPSAICIN = 8, REAGENT_ID_CONDENSEDCAPSAICIN = 8)


/obj/item/reagent_containers/food/snacks/meat/eelmeat
	name = "Eel Meat"
	desc = "A slice from an eel"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 3, REAGENT_ID_SHOCKCHEM = 1)


/obj/item/reagent_containers/food/snacks/meat/gravityshell
	name = "Gravity Shell Meat"
	desc = "A slice from a gravity shell"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 24)


//ant meats
/obj/item/reagent_containers/food/snacks/tyrant_shock
	name = "Shocking Ant Slice"
	desc = "A slice from a ant"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_SHOCKCHEM = 5)
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/copperant)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_SHOCKCHEM = 5)))

/obj/item/reagent_containers/food/snacks/tyrant_neoburn
	name = "Painite Ant Slice"
	desc = "A slice from a ant"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_NEOLIQUIDFIRE = 5)
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/painiteant)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_NEOLIQUIDFIRE = 5)))


/obj/item/reagent_containers/food/snacks/tyrant_burn
	name = "Bronze Ant Slice"
	desc = "A slice from a ant"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_LIQUIDFIRE = 5)
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tyrant_burn)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_LIQUIDFIRE = 5)))

/obj/item/reagent_containers/food/snacks/tyrant_radiation
	name = "Quartz Ant Slice"
	desc = "A slice from a ant"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_DEATHBLOOD = 5)
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tyrant_radiation)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_DEATHBLOOD = 5)))

/obj/item/reagent_containers/food/snacks/tyrant_bonus
	name = "Agate Ant Slice"
	desc = "A slice from a ant"
	icon_state = "meat"
	center_of_mass_x = 17
	center_of_mass_y= 16
	nutriment_amt = 3
	nutriment_desc = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_LIQUIDLIFE = 5)
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tyrant_bonus)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 5, REAGENT_ID_LIQUIDLIFE = 5)))
