
///////////////////////////////////////////////Condiments
//Notes by Darem: The condiments food-subtype is for stuff you don't actually eat but you use to modify existing food. They all
//	leave empty containers when used up and can be filled/re-filled with other items. Formatting for first section is identical
//	to mixed-drinks code. If you want an object that starts pre-loaded, you need to make it in addition to the other code.

//Food items that aren't eaten normally and leave an empty container behind.
/obj/item/reagent_containers/food/condiment
	name = "Condiment Container"
	desc = "Just your average condiment container."
	icon = 'icons/obj/food.dmi'
	icon_state = "emptycondiment"
	min_transfer_amount = 1
	amount_per_transfer_from_this = 2
	max_transfer_amount = 10
	center_of_mass_x = 16
	center_of_mass_y = 6
	volume = 50
	/// The bottle is named, described and drawn for the reagent it holds most of (a small shaker, a packet, the spice bottle and a carton keep their own looks).
	var/looks_like_contents = TRUE

// A condiment is a holder of its volume that is always open: sipped by yourself and fed to others in three seconds (in any stance), poured into an open container,
// filled from a tank, and added to a solid food (which is not open) by the amount set.
CAPABILITIES(/obj/item/reagent_containers/food/condiment)
	reagent_container(
		volume = nameof(volume),
		taps = list(/obj/structure/reagent_dispensers),
		feed = TRUE,
		splash = FALSE,
		ingest_hostile = TRUE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this),
		transfer_min = nameof(min_transfer_amount),
		transfer_max = nameof(max_transfer_amount))
	op("season", at_target(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), label("Add to it"),
		needs(req_reagents(1, because = MSG(condiment/none_left)), req_reagent_room(because = MSG(condiment/no_room))),
		costs(RES_REAGENTS, PROC_REF(season_amount)), says(MSG(condiment/season)))
	extend("reagent_container.drink", says(MSG(condiment/swallow)), then(PROC_REF(swallowed)))
	extend("reagent_container.feed", then(PROC_REF(swallowed)))

MSG_DEF_SELF(condiment/none_left, "There is no condiment left in it.")
MSG_DEF_SELF(condiment/no_room, "You can't add more condiment to it.")
MSG_DEF(condiment/season, "You add some of the condiment to %T%.", "%U% adds some of the condiment to %T%.")
MSG_DEF(condiment/swallow, "You swallow some of the contents of %I%.", "%U% swallows some of %I%.")

/// How much of the bottle goes on a food: the amount set, no more than it holds and the food takes.
/obj/item/reagent_containers/food/condiment/proc/season_amount(datum/act/op/A)
	var/atom/food = A.target
	return min(reagent_transfer_amount(src), reagents_giveable(src), reagents_takeable(food))

/// A sip, or a feeding: the sound of it.
/obj/item/reagent_containers/food/condiment/proc/swallowed(datum/act/op/A)
	play_sfx(src, SFX_ITEMS_DRINK, volume = rand(10, 50))
	return OP_OK

/// What a bottle looks like for the reagent that is most of it: list(name, description, icon state, centre of mass x, centre of mass y).
/obj/item/reagent_containers/food/condiment/proc/looks_for(reagent_id)
	var/static/list/looks = list(
		REAGENT_ID_KETCHUP = list(REAGENT_KETCHUP, "You feel more American already.", "ketchup", 16, 6),
		REAGENT_ID_MUSTARD = list(REAGENT_MUSTARD, "A somewhat bitter topping.", "mustard", 16, 6),
		REAGENT_ID_CAPSAICIN = list("Hotsauce", "You can almost TASTE the stomach ulcers now!", "hotsauce", 16, 6),
		REAGENT_ID_ENZYME = list(REAGENT_ENZYME, "Used in cooking various dishes.", "enzyme", 16, 6),
		REAGENT_ID_SOYSAUCE = list(REAGENT_SOYSAUCE, "A salty soy-based flavoring.", "soysauce", 16, 6),
		REAGENT_ID_VINEGAR = list(REAGENT_VINEGAR, "An acetic acid used in various dishes.", "vinegar", 16, 6),
		REAGENT_ID_FROSTOIL = list("Coldsauce", "Leaves the tongue numb in its passage.", "coldsauce", 16, 6),
		REAGENT_ID_SODIUMCHLORIDE = list("Salt Shaker", "Salt. From space oceans, presumably.", "saltshaker", 17, 11),
		REAGENT_ID_BLACKPEPPER = list("Pepper Mill", "Often used to flavor food or make people sneeze.", "peppermillsmall", 17, 11),
		REAGENT_ID_COOKINGOIL = list(REAGENT_COOKINGOIL, "A delicious oil used in cooking. General purpose.", "oliveoil", 16, 6),
		REAGENT_ID_SUGAR = list(REAGENT_SUGAR, "Tastey space sugar!", null, 16, 6), // the old bottle kept whatever picture it had
		REAGENT_ID_PEANUTBUTTER = list(REAGENT_PEANUTBUTTER, "A jar of smooth peanut butter.", "peanutbutter", 16, 6),
		REAGENT_ID_MAYO = list(REAGENT_MAYO, "A jar of mayonnaise!", "mayo", 16, 6),
		REAGENT_ID_YEAST = list(REAGENT_YEAST, "This is what you use to make bread fluffy.", "yeast", 16, 6),
		REAGENT_ID_SPACESPICE = list("bottle of space spice", "An exotic blend of spices for cooking. Definitely not worms.", "spacespicebottle", 16, 6),
		REAGENT_ID_BARBECUE = list("barbecue sauce", "Barbecue sauce, it's labeled 'sweet and spicy'.", "barbecue", 16, 6),
		REAGENT_ID_SPRINKLES = list(REAGENT_ID_SPRINKLES, "Bottle of sprinkles, colourful!", "sprinkles", 16, 6))
	return looks[reagent_id]

/obj/item/reagent_containers/food/condiment/on_reagent_change()
	if(!looks_like_contents)
		return
	if(!length(reagents.reagent_list))
		icon_state = "emptycondiment"
		name = "Condiment Bottle"
		desc = "An empty condiment bottle."
		center_of_mass_x = 16
		center_of_mass_y = 6
		return
	var/list/look = looks_for(reagents.get_master_reagent_id())
	if(look)
		name = look[1]
		desc = look[2]
		if(look[3])
			icon_state = look[3]
		center_of_mass_x = look[4]
		center_of_mass_y = look[5]
		return
	name = "Misc Condiment Bottle"
	if(length(reagents.reagent_list) == 1)
		desc = "Looks like it is [reagents.get_master_reagent_name()], but you are not sure."
	else
		desc = "A mixture of various condiments. [reagents.get_master_reagent_name()] is one of them."
	icon_state = "mixedcondiments"
	center_of_mass_x = 16
	center_of_mass_y = 6

/obj/item/reagent_containers/food/condiment/enzyme
	name = REAGENT_ENZYME
	desc = "Used in cooking various dishes."
	icon_state = "enzyme"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/enzyme)
	configure(reagents(add = list(REAGENT_ID_ENZYME = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/sugar)
	configure(reagents(add = list(REAGENT_ID_SUGAR = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/ketchup)
	configure(reagents(add = list(REAGENT_ID_KETCHUP = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/mustard)
	configure(reagents(add = list(REAGENT_ID_MUSTARD = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/hotsauce)
	configure(reagents(add = list(REAGENT_ID_CAPSAICIN = 50)))

/obj/item/reagent_containers/food/condiment/cookingoil
	name = REAGENT_COOKINGOIL

CAPABILITIES(/obj/item/reagent_containers/food/condiment/cookingoil)
	configure(reagents(add = list(REAGENT_ID_COOKINGOIL = 50)))

/obj/item/reagent_containers/food/condiment/cornoil
	name = REAGENT_CORNOIL

CAPABILITIES(/obj/item/reagent_containers/food/condiment/cornoil)
	configure(reagents(add = list(REAGENT_ID_CORNOIL = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/coldsauce)
	configure(reagents(add = list(REAGENT_ID_FROSTOIL = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/soysauce)
	configure(reagents(add = list(REAGENT_ID_SOYSAUCE = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/vinegar)
	configure(reagents(add = list(REAGENT_ID_VINEGAR = 50)))

/obj/item/reagent_containers/food/condiment/yeast
	name = REAGENT_YEAST

CAPABILITIES(/obj/item/reagent_containers/food/condiment/yeast)
	configure(reagents(add = list(REAGENT_ID_YEAST = 50)))

/obj/item/reagent_containers/food/condiment/sprinkles
	name = REAGENT_SPRINKLES

CAPABILITIES(/obj/item/reagent_containers/food/condiment/sprinkles)
	configure(reagents(add = list(REAGENT_ID_SPRINKLES = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/condiment/barbeque)
	configure(reagents(add = list(REAGENT_ID_BARBECUE = 50)))

/obj/item/reagent_containers/food/condiment/small
	max_transfer_amount = 20
	min_transfer_amount = 1
	amount_per_transfer_from_this = 1
	volume = 20
	center_of_mass_x = 0
	center_of_mass_y = 0
	looks_like_contents = FALSE

/obj/item/reagent_containers/food/condiment/small/saltshaker	//Seperate from above since it's a small shaker rather then
	name = "salt shaker"											//	a large one.
	desc = "Salt. From space oceans, presumably."
	icon_state = "saltshakersmall"
	center_of_mass_x = 17
	center_of_mass_y = 11

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/saltshaker)
	configure(reagents(add = list(REAGENT_ID_SODIUMCHLORIDE = 20)))

/obj/item/reagent_containers/food/condiment/small/peppermill //Keeping name here to save map based headaches
	name = "pepper shaker"
	desc = "Often used to flavor food or make people sneeze."
	icon_state = "peppershakersmall"
	center_of_mass_x = 17
	center_of_mass_y = 11

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/peppermill)
	configure(reagents(add = list(REAGENT_ID_BLACKPEPPER = 20)))

/obj/item/reagent_containers/food/condiment/small/peppergrinder
	name = "pepper mill"
	desc = "Fancy way to season a dish or make people sneeze."
	icon_state = "peppermill"
	center_of_mass_x = 17
	center_of_mass_y = 11

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/peppergrinder)
	configure(reagents(add = list(REAGENT_ID_BLACKPEPPER = 30)))

/obj/item/reagent_containers/food/condiment/small/sugar
	name = REAGENT_ID_SUGAR
	desc = "Sweetness in a bottle"
	icon_state = "sugarsmall"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/sugar)
	configure(reagents(add = list(REAGENT_ID_SUGAR = 20)))

//MRE condiments and drinks.

/obj/item/reagent_containers/food/condiment/small/packet
	icon_state = "packet_small"
	w_class = ITEMSIZE_TINY
	max_transfer_amount = 5
	min_transfer_amount = 1
	amount_per_transfer_from_this = 1
	volume = 5

/obj/item/reagent_containers/food/condiment/small/packet/salt
	name = "salt packet"
	desc = "Contains 5u of table salt."
	icon_state = "packet_small_white"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/salt)
	configure(reagents(add = list(REAGENT_ID_SODIUMCHLORIDE = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/pepper
	name = "pepper packet"
	desc = "Contains 5u of black pepper."
	icon_state = "packet_small_black"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/pepper)
	configure(reagents(add = list(REAGENT_ID_BLACKPEPPER = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/sugar
	name = "sugar packet"
	desc = "Contains 5u of refined sugar."
	icon_state = "packet_small_white"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/sugar)
	configure(reagents(add = list(REAGENT_ID_SUGAR = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/jelly
	name = "jelly packet"
	desc = "Contains 10u of cherry jelly. Best used for spreading on crackers."
	icon_state = "packet_medium"
	volume = 10

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/jelly)
	configure(reagents(add = list(REAGENT_ID_CHERRYJELLY = 10)))

/obj/item/reagent_containers/food/condiment/small/packet/honey
	name = "honey packet"
	desc = "Contains 10u of honey."
	icon_state = "packet_medium"
	volume = 10

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/honey)
	configure(reagents(add = list(REAGENT_ID_HONEY = 10)))

/obj/item/reagent_containers/food/condiment/small/packet/capsaicin
	name = "hot sauce packet"
	desc = "Contains 5u of hot sauce. Enjoy in moderation."
	icon_state = "packet_small_red"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/capsaicin)
	configure(reagents(add = list(REAGENT_ID_CAPSAICIN = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/ketchup
	name = "ketchup packet"
	desc = "Contains 5u of ketchup."
	icon_state = "packet_small_red"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/ketchup)
	configure(reagents(add = list(REAGENT_ID_KETCHUP = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/mayo
	name = "mayonnaise packet"
	desc = "Contains 5u of mayonnaise."
	icon_state = "packet_small_white"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/mayo)
	configure(reagents(add = list(REAGENT_ID_MAYO = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/soy
	name = "soy sauce packet"
	desc = "Contains 5u of soy sauce."
	icon_state = "packet_small_black"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/soy)
	configure(reagents(add = list(REAGENT_ID_SOYSAUCE = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/coffee
	name = "coffee powder packet"
	desc = "Contains 5u of coffee powder. Mix with 25u of water and heat."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/coffee)
	configure(reagents(add = list(REAGENT_ID_COFFEEPOWDER = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/tea
	name = "tea powder packet"
	desc = "Contains 5u of black tea powder. Mix with 25u of water and heat."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/tea)
	configure(reagents(add = list(REAGENT_ID_TEA = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/cocoa
	name = "cocoa powder packet"
	desc = "Contains 5u of cocoa powder. Mix with 25u of water and heat."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/cocoa)
	configure(reagents(add = list(REAGENT_ID_COCO = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/grape
	name = "grape juice powder packet"
	desc = "Contains 5u of powdered grape juice. Mix with 15u of water."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/grape)
	configure(reagents(add = list(REAGENT_ID_INSTANTGRAPE = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/orange
	name = "orange juice powder packet"
	desc = "Contains 5u of powdered orange juice. Mix with 15u of water."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/orange)
	configure(reagents(add = list(REAGENT_ID_INSTANTORANGE = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/watermelon
	name = "watermelon juice powder packet"
	desc = "Contains 5u of powdered watermelon juice. Mix with 15u of water."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/watermelon)
	configure(reagents(add = list(REAGENT_ID_INSTANTWATERMELON = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/apple
	name = "apple juice powder packet"
	desc = "Contains 5u of powdered apple juice. Mix with 15u of water."

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/apple)
	configure(reagents(add = list(REAGENT_ID_INSTANTAPPLE = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/protein
	name = "protein powder packet"
	desc = "Contains 10u of powdered protein. Mix with 20u of water."
	icon_state = "packet_medium"
	volume = 10

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/protein)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 10)))

/obj/item/reagent_containers/food/condiment/small/packet/crayon
	name = "crayon powder packet"
	desc = "Contains 10u of powdered crayon. Mix with 30u of water."
	volume = 10
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/generic)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUST = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/red)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTRED = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/orange)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTORANGE = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/yellow)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTYELLOW = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/green)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTGREEN = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/blue)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTBLUE = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/purple)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTPURPLE = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/grey)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTGREY = 10)))
CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/crayon/brown)
	configure(reagents(add = list(REAGENT_ID_CRAYONDUSTBROWN = 10)))

//End of MRE stuff.

/// A carton draws how full it is, by quarters.
/obj/item/reagent_containers/food/condiment/carton
	looks_like_contents = FALSE

/obj/item/reagent_containers/food/condiment/carton/draw(datum/look/look)
	. = ..()
	look.watch(reagents)
	if(reagents.total_volume && volume)
		look.overlay("[icon_state]-[clamp(round(100 * reagents.total_volume / volume, 25), 0, 100)]")

/obj/item/reagent_containers/food/condiment/carton/flour
	name = "flour carton"
	desc = "A big carton of flour. Good for baking!"
	icon = 'icons/obj/food.dmi'
	icon_state = "flour"
	volume = 220
	center_of_mass_x = 16
	center_of_mass_y = 8
	amount_per_transfer_from_this = 5


CAPABILITIES(/obj/item/reagent_containers/food/condiment/carton/flour)
	configure(reagents(add = list(REAGENT_ID_FLOUR = 200)))
	rolls(ROLL_PIXEL, PIXEL_JITTER(nameof(randpixel)))

/obj/item/reagent_containers/food/condiment/carton/flour/rustic
	name = "flour sack"
	desc = "An artisanal sack of flour. Classy!"
	icon_state = "flour_bag"

/obj/item/reagent_containers/food/condiment/carton/sugar
	name = "sugar carton"
	desc = "A big carton of sugar. Sweet!"
	icon_state = REAGENT_ID_SUGAR
	volume = 120
	center_of_mass_x = 16
	center_of_mass_y = 8
	amount_per_transfer_from_this = 5

CAPABILITIES(/obj/item/reagent_containers/food/condiment/carton/sugar)
	configure(reagents(add = list(REAGENT_ID_SUGAR = 100)))

/obj/item/reagent_containers/food/condiment/carton/sugar/rustic
	name = "sugar sack"
	desc = "An artisanal sack of sugar. Classy!"
	icon_state = "sugar_bag"

/obj/item/reagent_containers/food/condiment/spacespice
	name = "space spices"
	desc = "An exotic blend of spices for cooking. Definitely not worms."
	icon_state = "spacespicebottle"
	max_transfer_amount = 40
	amount_per_transfer_from_this = 1
	volume = 40
	looks_like_contents = FALSE

CAPABILITIES(/obj/item/reagent_containers/food/condiment/spacespice)
	configure(reagents(add = list(REAGENT_ID_SPACESPICE = 40)))

/obj/item/reagent_containers/food/condiment/small/packet/protein_powder
	name = "protein powder packet"
	desc = "Contains 5u of regular protein powder. Mix with 25u of water and enjoy."
	icon_state = "protein_powder1"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/protein_powder)
	configure(reagents(add = list(REAGENT_ID_PROTEINPOWDER = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/vanilla
	name = "vanilla protein powder packet"
	desc = "Contains 5u of vanilla flavored protein powder. Mix with 25u of water and enjoy."
	icon_state = "protein_powder2"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/vanilla)
	configure(reagents(add = list(REAGENT_ID_VANILLAPROTEINPOWDER = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/banana
	name = "banana protein powder packet"
	desc = "Contains 5u of banana flavored protein powder. Mix with 25u of water and enjoy."
	icon_state = "protein_powder3"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/banana)
	configure(reagents(add = list(REAGENT_ID_BANANAPROTEINPOWDER = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/chocolate
	name = "chocolate protein powder packet"
	desc = "Contains 5u of chocolate flavored protein powder. Mix with 25u of water and enjoy."
	icon_state = "protein_powder4"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/chocolate)
	configure(reagents(add = list(REAGENT_ID_CHOCOLATEPROTEINPOWDER = 5)))

/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/strawberry
	name = "strawberry protein powder packet"
	desc = "Contains 5u of strawberry flavored protein powder. Mix with 25u of water and enjoy."
	icon_state = "protein_powder5"

CAPABILITIES(/obj/item/reagent_containers/food/condiment/small/packet/protein_powder/strawberry)
	configure(reagents(add = list(REAGENT_ID_STRAWBERRYPROTEINPOWDER = 5)))
