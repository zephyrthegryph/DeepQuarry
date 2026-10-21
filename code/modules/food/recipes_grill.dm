// Alt recipie doesn't need to be shown(breaks tgui)
/transformation/kitchen/humanburger
CAPABILITIES(/transformation/kitchen/humanburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat/human, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/human/burger, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

// do not place this recipe before /transformation/kitchen/humanburger
// do not place this recipe before /transformation/kitchen/humanburger
/transformation/kitchen/plainburger
CAPABILITIES(/transformation/kitchen/plainburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeyburger, 1)),
		cooks_in = GRILL))

// Alt recipie doesn't need to be shown(breaks tgui)
/transformation/kitchen/syntiburger
CAPABILITIES(/transformation/kitchen/syntiburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeyburger, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

/transformation/kitchen/brainburger
CAPABILITIES(/transformation/kitchen/brainburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/organ/internal/brain, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/brainburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/roburger
CAPABILITIES(/transformation/kitchen/roburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/robot_parts/head, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/roburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/xenoburger
CAPABILITIES(/transformation/kitchen/xenoburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/xenoburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/fishburger
CAPABILITIES(/transformation/kitchen/fishburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/fishburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/tofuburger
CAPABILITIES(/transformation/kitchen/tofuburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tofuburger, 1)),
		cooks_in = GRILL))

// where do you even find this stuff
// where do you even find this stuff
/transformation/kitchen/ghostburger
CAPABILITIES(/transformation/kitchen/ghostburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/ectoplasm, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/ghostburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/clownburger
CAPABILITIES(/transformation/kitchen/clownburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/clothing/mask/gas/clown_hat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/clownburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/mimeburger
CAPABILITIES(/transformation/kitchen/mimeburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/clothing/head/beret, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mimeburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/mouseburger
CAPABILITIES(/transformation/kitchen/mouseburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/holder/mouse, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/mouseburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/bunbun
CAPABILITIES(/transformation/kitchen/bunbun)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bunbun, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

/transformation/kitchen/hotdog
CAPABILITIES(/transformation/kitchen/hotdog)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sausage, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/hotdog, 1)),
		cooks_in = GRILL))

/transformation/kitchen/humankabob
CAPABILITIES(/transformation/kitchen/humankabob)
	configure(transformation(takes = list(item_term(/obj/item/stack/rods, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/human, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/human, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/human/kabob, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

// Do not put before humankabob
/transformation/kitchen/kabob
CAPABILITIES(/transformation/kitchen/kabob)
	configure(transformation(takes = list(item_term(/obj/item/stack/rods, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeykabob, 1)),
		cooks_in = GRILL))

// Alt recipie doesn't need to be shown(breaks tgui)
/transformation/kitchen/monkeykabob
CAPABILITIES(/transformation/kitchen/monkeykabob)
	configure(transformation(takes = list(item_term(/obj/item/stack/rods, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/monkey, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/monkey, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeykabob, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

// Alt recipie doesn't need to be shown(breaks tgui)
/transformation/kitchen/syntikabob
CAPABILITIES(/transformation/kitchen/syntikabob)
	configure(transformation(takes = list(item_term(/obj/item/stack/rods, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeykabob, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

/transformation/kitchen/tofukabob
CAPABILITIES(/transformation/kitchen/tofukabob)
	configure(transformation(takes = list(item_term(/obj/item/stack/rods, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/tofu, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/tofukabob, 1)),
		cooks_in = GRILL))

/transformation/kitchen/fakespellburger
CAPABILITIES(/transformation/kitchen/fakespellburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeyburger, 1),
			item_term(/obj/item/clothing/head/wizard/fake, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/spellburger, 1)),
		cooks_in = GRILL,
		wiki = WIKI_SPOILER))

/transformation/kitchen/spellburger
CAPABILITIES(/transformation/kitchen/spellburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeyburger, 1),
			item_term(/obj/item/clothing/head/wizard, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/spellburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/bigbiteburger
CAPABILITIES(/transformation/kitchen/bigbiteburger)
	configure(transformation(takes = list(reagent(REAGENT_ID_EGG, 3),
			item_term(/obj/item/reagent_containers/food/snacks/monkeyburger, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bigbiteburger, 1)),
		cooks_in = GRILL,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/superbiteburger
CAPABILITIES(/transformation/kitchen/superbiteburger)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 5),
			reagent(REAGENT_ID_BLACKPEPPER, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bigbiteburger, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/boiledegg, 1),
			fruit_term(PLANT_TOMATO, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/superbiteburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/slimeburger
CAPABILITIES(/transformation/kitchen/slimeburger)
	configure(transformation(takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jellyburger/slime, 1)),
		cooks_in = GRILL))

/transformation/kitchen/jellyburger
CAPABILITIES(/transformation/kitchen/jellyburger)
	configure(transformation(takes = list(reagent(REAGENT_ID_CHERRYJELLY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/jellyburger/cherry, 1)),
		cooks_in = GRILL))

/transformation/kitchen/bearburger
CAPABILITIES(/transformation/kitchen/bearburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bearmeat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bearburger, 1)),
		cooks_in = GRILL))

/transformation/kitchen/baconburger
CAPABILITIES(/transformation/kitchen/baconburger)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/bun, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bacon, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burger/bacon, 1)),
		cooks_in = GRILL))

/transformation/kitchen/omelette
CAPABILITIES(/transformation/kitchen/omelette)
	configure(transformation(takes = list(reagent(REAGENT_ID_EGG, 6),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/omelette, 1)),
		cooks_in = GRILL,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/omurice
CAPABILITIES(/transformation/kitchen/omurice)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 5),
			reagent(REAGENT_ID_KETCHUP, 5),
			reagent(REAGENT_ID_EGG, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/omurice, 1)),
		cooks_in = GRILL))

/transformation/kitchen/omurice/heart
CAPABILITIES(/transformation/kitchen/omurice/heart)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 5),
			reagent(REAGENT_ID_KETCHUP, 5),
			reagent(REAGENT_ID_SUGAR, 5),
			reagent(REAGENT_ID_EGG, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/omurice/heart, 1)),
		cooks_in = GRILL))

/transformation/kitchen/omurice/face
CAPABILITIES(/transformation/kitchen/omurice/face)
	configure(transformation(takes = list(reagent(REAGENT_ID_RICE, 5),
			reagent(REAGENT_ID_KETCHUP, 5),
			reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_EGG, 3)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/omurice/face, 1)),
		cooks_in = GRILL))

/transformation/kitchen/meatsteak
CAPABILITIES(/transformation/kitchen/meatsteak)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1),
			reagent(REAGENT_ID_BLACKPEPPER, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/meatsteak, 1)),
		cooks_in = GRILL))

// Simplify end product
/transformation/kitchen/honeytoast
CAPABILITIES(/transformation/kitchen/honeytoast)
	configure(transformation(takes = list(reagent(REAGENT_ID_HONEY, 5),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/honeytoast, 1)),
		cooks_in = GRILL,
		mix = RECIPE_REAGENT_REPLACE))

/transformation/kitchen/grilled_carp
CAPABILITIES(/transformation/kitchen/grilled_carp)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_LETTUCE, 1),
			fruit_term(PLANT_LIME, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/grilled_carp, 1)),
		cooks_in = GRILL))

/transformation/kitchen/grilledcheese
CAPABILITIES(/transformation/kitchen/grilledcheese)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/grilledcheese, 1)),
		cooks_in = GRILL))

/transformation/kitchen/toastedsandwich
CAPABILITIES(/transformation/kitchen/toastedsandwich)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sandwich, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/toastedsandwich, 1)),
		cooks_in = GRILL))

/transformation/kitchen/cheese_cracker
CAPABILITIES(/transformation/kitchen/cheese_cracker)
	configure(transformation(takes = list(reagent(REAGENT_ID_SPACESPICE, 1),
			item_term(/obj/item/reagent_containers/food/snacks/spreads/butter, 1),
			item_term(/obj/item/reagent_containers/food/snacks/slice/bread, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesetoast, 4)),
		cooks_in = GRILL))

/transformation/kitchen/bacongrill
CAPABILITIES(/transformation/kitchen/bacongrill)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/spreads, 1),
			item_term(/obj/item/reagent_containers/food/snacks/rawbacon, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/bacon, 1)),
		cooks_in = GRILL))

// Also just combinable, like burgers and hot dogs.
/transformation/kitchen/chickenfillet
CAPABILITIES(/transformation/kitchen/chickenfillet)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/chickenkatsu, 1),
			item_term(/obj/item/reagent_containers/food/snacks/bun, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/chickenfillet, 1)),
		cooks_in = GRILL))

/transformation/kitchen/burgerpatty
CAPABILITIES(/transformation/kitchen/burgerpatty)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/rawcutlet, 1)),
		makes = list(item_term(/obj/item/reagent_containers/food/snacks/burgerpatty, 1)),
		cooks_in = GRILL))
