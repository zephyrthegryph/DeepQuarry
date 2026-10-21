//The collection of everything 'cake' related
// adjust recipes, make ingredients mobs

/transformation/kitchen/thecake_firstlayer
CAPABILITIES(/transformation/kitchen/thecake_firstlayer)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 500),
			reagent(REAGENT_ID_MILK, 200),
			reagent(REAGENT_ID_SUGAR, 200),
			reagent(REAGENT_ID_EGG, 100),
			item_term(/obj/item/stack/material/silver, 1),
			item_term(/obj/item/stack/material/silver, 1),
			item_term(/obj/item/stack/material/silver, 1),
			item_term(/obj/item/stack/material/silver, 1),
			item_term(/obj/item/stack/material/silver, 1),
			item_term(/obj/item/slime_extract/grey, 1),
			item_term(/obj/item/slime_extract/grey, 1),
			item_term(/obj/item/slime_extract/grey, 1),
			item_term(/obj/item/slime_extract/grey, 1),
			item_term(/obj/item/slime_extract/grey, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 1),
			fruit_term(PLANT_ICECHILI, 30),
			fruit_term(PLANT_PLASTIC, 15)),
		makes = list(item_term(/obj/structure/thecake, 1))))

/transformation/kitchen/thecake_secondlayer
CAPABILITIES(/transformation/kitchen/thecake_secondlayer)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 400),
			reagent(REAGENT_ID_MILK, 200),
			reagent(REAGENT_ID_SUGAR, 100),
			reagent(REAGENT_ID_CRYOXADONE, 200),
			reagent(REAGENT_ID_FROSTOIL, 100),
			item_term(/obj/item/stack/material/glass/phoronglass, 1),
			item_term(/obj/item/stack/material/glass/phoronglass, 1),
			item_term(/obj/item/stack/material/glass/phoronglass, 1),
			item_term(/obj/item/stack/material/glass/phoronglass, 1),
			item_term(/obj/item/stack/material/glass/phoronglass, 1),
			item_term(/obj/item/organ/internal/eyes, 1),
			item_term(/obj/item/organ/internal/eyes, 1),
			item_term(/obj/item/organ/internal/eyes, 1),
			item_term(/obj/item/organ/internal/eyes, 1),
			item_term(/obj/item/organ/internal/eyes, 1),
			item_term(/obj/item/stack/material/diamond, 1),
			item_term(/obj/item/stack/material/diamond, 1),
			item_term(/obj/item/stack/material/diamond, 1),
			item_term(/obj/item/stack/material/diamond, 1),
			item_term(/obj/item/stack/material/diamond, 1),
			fruit_term(PLANT_VANILLA, 30),
			fruit_term(PLANT_SIFLETTUCE, 15)),
		makes = list(item_term(/obj/item/thecake_layer, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/thecake_thirdlayer
CAPABILITIES(/transformation/kitchen/thecake_thirdlayer)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 300),
			reagent(REAGENT_ID_SINGULO, 300),
			reagent(REAGENT_ID_ATOMICBOMB, 150),
			reagent(REAGENT_ID_THREEMILEISLAND, 150),
			reagent(REAGENT_ID_MANHATTANPROJ, 100),
			item_term(/obj/item/stack/material/uranium, 1),
			item_term(/obj/item/stack/material/uranium, 1),
			item_term(/obj/item/stack/material/uranium, 1),
			item_term(/obj/item/stack/material/uranium, 1),
			item_term(/obj/item/stack/material/uranium, 1),
			item_term(/obj/item/slime_extract/green, 1),
			item_term(/obj/item/slime_extract/green, 1),
			item_term(/obj/item/slime_extract/green, 1),
			item_term(/obj/item/slime_extract/green, 1),
			item_term(/obj/item/slime_extract/green, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/carpmeat, 1),
			fruit_term(PLANT_GLOWBERRIES, 30),
			fruit_term(PLANT_GLOWSHROOM, 15)),
		makes = list(item_term(/obj/item/thecake_layer/three, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/thecake_fourthlayer
CAPABILITIES(/transformation/kitchen/thecake_fourthlayer)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 400),
			reagent(REAGENT_ID_HOLYMARY, 100),
			reagent(REAGENT_ID_ANGELSKISS, 100),
			reagent(REAGENT_ID_GOLDSCHLAGER, 100),
			reagent(REAGENT_ID_GOLD, 300),
			item_term(/obj/item/stack/material/gold, 1),
			item_term(/obj/item/stack/material/gold, 1),
			item_term(/obj/item/stack/material/gold, 1),
			item_term(/obj/item/stack/material/gold, 1),
			item_term(/obj/item/stack/material/gold, 1),
			item_term(/obj/item/organ/internal/heart, 1),
			item_term(/obj/item/organ/internal/heart, 1),
			item_term(/obj/item/organ/internal/heart, 1),
			item_term(/obj/item/organ/internal/heart, 1),
			item_term(/obj/item/organ/internal/heart, 1),
			item_term(/obj/item/reagent_containers/food/snacks/appletart, 1),
			item_term(/obj/item/reagent_containers/food/snacks/appletart, 1),
			item_term(/obj/item/reagent_containers/food/snacks/appletart, 1),
			item_term(/obj/item/reagent_containers/food/snacks/appletart, 1),
			item_term(/obj/item/reagent_containers/food/snacks/appletart, 1),
			fruit_term(PLANT_AMBROSIADEUS, 30),
			fruit_term(PLANT_GOLDAPPLE, 15)),
		makes = list(item_term(/obj/item/thecake_layer/four, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/thecake_fifthlayer
CAPABILITIES(/transformation/kitchen/thecake_fifthlayer)
	configure(transformation(takes = list(reagent(REAGENT_ID_DEATHBELL, 1000),
			item_term(/obj/item/stack/material/platinum, 1),
			item_term(/obj/item/stack/material/platinum, 1),
			item_term(/obj/item/stack/material/platinum, 1),
			item_term(/obj/item/stack/material/platinum, 1),
			item_term(/obj/item/stack/material/platinum, 1),
			item_term(/obj/item/slime_extract/emerald, 1),
			item_term(/obj/item/slime_extract/emerald, 1),
			item_term(/obj/item/slime_extract/emerald, 1),
			item_term(/obj/item/slime_extract/emerald, 1),
			item_term(/obj/item/slime_extract/emerald, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/xenomeat, 1),
			fruit_term(PLANT_LIBERTYCAP, 10),
			fruit_term(PLANT_DEATHNETTLE, 10),
			fruit_term(PLANT_DESTROYINGANGEL, 10)),
		makes = list(item_term(/obj/item/thecake_layer/five, 1)),
		wiki = WIKI_SPOILER))

/obj/structure/thecake/proc/HasSliceMissing()
	if(slices < maxslices)
		if(interval >= regentime)
			set_interval(0)
			slices++
			HasSliceMissing()
		else
			set_interval(interval + 1)
			HasSliceMissing()
	else
		return

/obj/item/thecake_layer
	name = "A layer of cake"
	desc = "a layer of cake, you can see your own reflection in it."
	icon = 'icons/obj/food_ch.dmi'
	var/layer_stage = 1
	icon_state = "thecake_layer-1"

/obj/item/thecake_layer/three
	desc = "a layer of cake, it bathes you in a soft green glowth and warmth."
	layer_stage = 2
	icon_state = "thecake_layer-2"

/obj/item/thecake_layer/four
	desc = "a layer of cake, its of so high karat that even the lightest touch leaves a dent in it."
	layer_stage = 3
	icon_state = "thecake_layer-3"

/obj/item/thecake_layer/five
	desc = "a layer of cake, whatever this strange metal thats used in it is, it seems to drawn in light and reflect it back in a different shade."
	layer_stage = 4
	icon_state = "thecake_layer-4"

/obj/item/thecake_layer/six
	name = "A stable singularity cherry"
	desc = "It's a tiny singularity, but it doesnt draw in everything around it, touching it feels strange, like your touching nothingness...That feels at the same time like touching a cherry."
	layer_stage = 5
	icon_state = "thecake_layer-5"

/obj/item/reagent_containers/food/snacks/thecakeslice
	name = "The Infinity Cake Slice"
	desc = "A slice from The Infinity Cake, sadly the slice itself isnt infinite..."
	icon = 'icons/obj/food_ch.dmi'
	icon_state = "thecakeslice"

	center_of_mass_x = 16
	center_of_mass_y= 10
	nutriment_desc = list("cake" = 10, "sweetness" = 10, "singularity?" = 1)
	nutriment_amt = 5
	//Add some randomized effect possibly, to make the slices special - Jack

/obj/structure/thecake
	name = "An unfinished cake"
	desc = "A single layer of tasty delicious cake goodness, but it feels very incomplete..."

	icon = 'icons/obj/food64x64_ch.dmi'
	icon_state = "thecake_onelayer"
	pixel_x = -16

	var/edible = 0
	var/stage = 1
	var/maxstages = 6
	var/slices = 5
	var/maxslices = 5

	var/regentime = 250 // considering the effort it takes to make this thing, 2000 meant it regenerated painfully slow.
	var/interval = 0
	var/static/list/desclist = list(
			"The lonely first layer of a magnificent cake. It looks tasty, just like momma used to bake.",
			"The second layer of the cake is added, the reflection makes it strange to look at.",
			"The third layer of cake sits in place now, it looks like it might kill you but it appears the second layer is an excellent radiation absorbant.",
			"The fourth layer of cake rests, so heavy the other layers starts to connect seamlessly as the dough warps.",
			"With the fifth layer messing with the light, the cake almost looks complete. It's just missing a centerpiece on top.",
			"its The Infinity Cake! This huge imposing cake made by immense efforts and resources stands tall in you, radiating a menacing aura of frosty goodness and diabetes for those not wary of it's infinite might!"
		)

CAPABILITIES(/obj/structure/thecake)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/thecake/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/material/knife))
		if(edible == 1)
			HasSliceMissing()
			if(slices <= 0)
				to_chat(user, span_warning("The cake hums away quietly as the singulo powered goodness slowly recovers the large amount of lost mass, best to give it a moment before cutting another slice."))
				return OP_PASS
			else
				to_chat(user, span_notice("You cut a slice of the cake. The slice looks like the cake was just baked, and you can see before your eyes as the spot where you cut the slice slowly regenerates!"))
				slices = slices - 1
				new /obj/item/reagent_containers/food/snacks/thecakeslice(src.loc)

		else
			to_chat(user, span_notice("It looks so good... But it feels so wrong to eat it before it's finished..."))
			return OP_PASS
	if(istype(W,/obj/item/thecake_layer))
		var/obj/item/thecake_layer/C = W
		if(C.layer_stage == 5)
			for(var/mob/O in view(src, null))
				O.show_message(span_warning("It has been done! The Infinity Cake has been assembled!"),1)
			consume(W, user)
			stage++
			desc = desclist[stage]
			set_icon_state("thecake_finished")
			edible = 1
			name = "The Infinity Cake!"
		else if(stage == maxstages)
			to_chat(user, span_warning("The cake is already done!"))
		else if(stage == C.layer_stage)
			to_chat(user, span_warning("You add another layer to the cake, nice."))
			consume(W, user)
			stage++
			desc = desclist[stage]
			set_icon_state("thecake_stage-[stage]")
		else
			to_chat(user, span_warning("Hmm, doesnt seem like this layer is supposed to be added there?"))
	return OP_PASS

// Chaos cake

/transformation/kitchen/chaoscake_layerone
CAPABILITIES(/transformation/kitchen/chaoscake_layerone)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 300),
			reagent(REAGENT_ID_MILK, 200),
			reagent(REAGENT_ID_SUGAR, 100),
			reagent(REAGENT_ID_EGG, 30),
			item_term(/obj/item/reagent_containers/food/snacks/meat/, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat/, 1),
			fruit_term(PLANT_POISONBERRIES, 15),
			fruit_term(PLANT_CHERRY, 15)),
		makes = list(item_term(/obj/structure/chaoscake, 1))))

/transformation/kitchen/chaoscake_layertwo
CAPABILITIES(/transformation/kitchen/chaoscake_layertwo)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 300),
			reagent(REAGENT_ID_MILK, 200),
			reagent(REAGENT_ID_SUGAR, 100),
			reagent(REAGENT_ID_EGG, 30),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_VANILLA, 15),
			fruit_term(PLANT_BANANA, 15)),
		makes = list(item_term(/obj/item/chaoscake_layer, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layerthree
CAPABILITIES(/transformation/kitchen/chaoscake_layerthree)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 240),
			reagent(REAGENT_ID_MILK, 150),
			reagent(REAGENT_ID_SUGAR, 80),
			reagent(REAGENT_ID_EGG, 24),
			reagent(REAGENT_ID_DEATHBELL, 100),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_GRAPES, 30)),
		makes = list(item_term(/obj/item/chaoscake_layer/three, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layerfour
CAPABILITIES(/transformation/kitchen/chaoscake_layerfour)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 240),
			reagent(REAGENT_ID_MILK, 150),
			reagent(REAGENT_ID_SUGAR, 80),
			reagent(REAGENT_ID_EGG, 24),
			reagent(REAGENT_ID_MILKSHAKE, 300),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_RICE, 30)),
		makes = list(item_term(/obj/item/chaoscake_layer/four, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layerfive
CAPABILITIES(/transformation/kitchen/chaoscake_layerfive)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 180),
			reagent(REAGENT_ID_MILK, 100),
			reagent(REAGENT_ID_SUGAR, 60),
			reagent(REAGENT_ID_EGG, 18),
			reagent(REAGENT_ID_BLOOD, 300),
			item_term(/obj/item/reagent_containers/food/snacks/lobster, 1),
			item_term(/obj/item/reagent_containers/food/snacks/lobster, 1),
			item_term(/obj/item/reagent_containers/food/snacks/lobster, 1),
			item_term(/obj/item/reagent_containers/food/snacks/lobster, 1),
			fruit_term(PLANT_TOMATO, 20)),
		makes = list(item_term(/obj/item/chaoscake_layer/five, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layersix
CAPABILITIES(/transformation/kitchen/chaoscake_layersix)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 180),
			reagent(REAGENT_ID_MILK, 100),
			reagent(REAGENT_ID_SUGAR, 60),
			reagent(REAGENT_ID_EGG, 18),
			reagent(REAGENT_ID_SPRINKLES, 10),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1),
			item_term(/obj/item/reagent_containers/food/snacks/chocolatebar, 1),
			fruit_term(PLANT_APPLE, 30)),
		makes = list(item_term(/obj/item/chaoscake_layer/six, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layerseven
CAPABILITIES(/transformation/kitchen/chaoscake_layerseven)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 120),
			reagent(REAGENT_ID_MILK, 50),
			reagent(REAGENT_ID_SUGAR, 40),
			reagent(REAGENT_ID_EGG, 12),
			reagent(REAGENT_ID_DEVILSKISS, 200),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_POTATO, 10)),
		makes = list(item_term(/obj/item/chaoscake_layer/seven, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layereight
CAPABILITIES(/transformation/kitchen/chaoscake_layereight)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLOUR, 120),
			reagent(REAGENT_ID_MILK, 50),
			reagent(REAGENT_ID_SUGAR, 40),
			reagent(REAGENT_ID_EGG, 12),
			reagent(REAGENT_ID_CREAM, 200),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/dough, 1),
			fruit_term(PLANT_LEMON, 10)),
		makes = list(item_term(/obj/item/chaoscake_layer/eight, 1)),
		wiki = WIKI_SPOILER))

/transformation/kitchen/chaoscake_layernine
CAPABILITIES(/transformation/kitchen/chaoscake_layernine)
	configure(transformation(takes = list(reagent(REAGENT_ID_WATER, 100),
			reagent(REAGENT_ID_BLOOD, 100),
			fruit_term(PLANT_GOLDAPPLE, 50)),
		makes = list(item_term(/obj/item/chaoscake_layer/nine, 1)),
		wiki = WIKI_SPOILER))

/obj/structure/chaoscake
	name = "An strange unfinished cake"
	desc = "A single layer of a strange cake, you can see the cherry paste ooze, but it feels very incomplete..."

	icon = 'icons/obj/food64x64.dmi'
	icon_state = "chaoscake_unfinished-1"
	pixel_x = -16

	var/slices = 6
	var/maxslices = 6
	var/stage = 1
	var/maxstages = 9
	var/edible = 0

	var/regentime = 1000
	var/interval = 0

	var/static/list/desclist2 = list(
			"The first layer of a strange cake, you can see the cherry paste ooze.",
			"The second layer of the cake sits in place now, smelling of pear with delicious colourful cream.",
			"The third layer of cake adds a strange purple layer, glazed over with frosting. It smells of grapes, but with a hint of something foul underneath.",
			"With the fourth layer added the cake looks happier again. Reeking of vanilla, it brings up memories of childhood joy.",
			"The fifth layer is extremely disturbing on that cake. Smelling of pure copper, it seems that bright blood clots are forming on top.",
			"The cake is getting closer with the sixth layer added, the pink hue smelling of chocolate, with colourful sprinkles on top.",
			"The first pair of triplets rest on the cake, despite being mostly similar to the first three, an evil aura becomes noticable.",
			"The second pair of triplets rest on the cake, if you stand on the bright side, you can feel a good aura lifting your mood.",
			"A chaos cake. Both a creation of dark and light, the two cakes are kept in a careful balance by that mystical coin in the middle. It's said its effects would dissipate if the balance is ever tipped in favour of one side too much, so both sides much be cut equally."
		)

/obj/item/chaoscake_layer
	name = "A layer of cake"
	desc = "a layer of cake, it is made out of colourful cream."
	icon = 'icons/obj/food.dmi'
	icon_state = "chaoscake_layer-2"
	var/layer_stage = 1

/obj/item/chaoscake_layer/three
	desc = "a layer of cake, glazed in purple."
	icon_state = "chaoscake_layer-3"
	layer_stage = 2

/obj/item/chaoscake_layer/four
	desc = "a layer of cake, reminding you of a colouring book."
	icon_state = "chaoscake_layer-4"
	layer_stage = 3

/obj/item/chaoscake_layer/five
	desc = "A layer of cake, smells like copper."
	icon_state = "chaoscake_layer-5"
	layer_stage = 4

/obj/item/chaoscake_layer/six
	desc = "A layer of cake, featuring colourful sprinkles."
	icon_state = "chaoscake_layer-6"
	layer_stage = 5

/obj/item/chaoscake_layer/seven
	desc = "A triplet of evil cake parts."
	icon_state = "chaoscake_layer-7"
	layer_stage = 6

/obj/item/chaoscake_layer/eight
	desc = "A triplet of good cake parts."
	icon_state = "chaoscake_layer-8"
	layer_stage = 7

/obj/item/chaoscake_layer/nine
	name = "A coin of balance"
	desc = "A very peculiar coin, it seems to stabilise the air around it."
	icon_state = "chaoscake_layer-9"
	layer_stage = 8

/obj/structure/chaoscake/proc/HasSliceMissing()
	if(slices < maxslices)
		if(interval >= regentime)
			set_interval(0)
			slices++
			HasSliceMissing()
		else
			set_interval(interval + 1)
			HasSliceMissing()
	else
		return

/obj/item/reagent_containers/food/snacks/chaoscakeslice
	name = "The Chaos Cake Slice"
	desc = "A slice from The Chaos Cake, it pulses weirdly, as if angry to be seperated from the whole"
	icon = 'icons/obj/food_ch.dmi'
	icon_state = "chaoscake_slice-1"

	center_of_mass_x = 16
	center_of_mass_y= 10
	nutriment_desc = list()
	nutriment_amt = 4
	volume = 80

/obj/item/reagent_containers/food/snacks/chaoscakeslice
	/// Which of the six slices it is (rolls()).
	var/slice_kind = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/chaoscakeslice)
	rolls(nameof(slice_kind), range_of(1, 6))
	rolls(nameof(icon_state), PROC_REF(roll_slice_icon), from = list(nameof(slice_kind)))
	rolls(nameof(name), PROC_REF(roll_slice_name), from = list(nameof(slice_kind)))
	rolls(nameof(desc), PROC_REF(roll_slice_desc), from = list(nameof(slice_kind)))
	rolls(nameof(bitesize), PROC_REF(roll_slice_bitesize), from = list(nameof(slice_kind)))
	configure(reagents(contents_from = PROC_REF(slice_contents), data = list(REAGENT_ID_NUTRIMENT = PROC_REF(slice_taste))))

TYPE_TABLE_DECLARE(/obj/item/reagent_containers/food/snacks/chaoscakeslice, chaos_slice_recipes, list(
	list(REAGENT_ID_NEUROTOXIC_PROTEIN = 2, REAGENT_ID_SHOCKCHEM = 2, REAGENT_ID_AMATOXIN = 2, REAGENT_ID_CARPOTOXIN = 2, REAGENT_ID_SPIDERTOXIN = 2),
	list(REAGENT_ID_STOXIN = 2, REAGENT_ID_BLISS = 10, REAGENT_ID_SEROTROTIUM = 4, REAGENT_ID_CRYPTOBIOLIN = 8, REAGENT_ID_MINDBREAKER = 10, REAGENT_ID_PSILOCYBIN = 10),
	list(REAGENT_ID_BLOOD = 20, REAGENT_ID_STOMACID = 10, REAGENT_ID_MUTAGEN = 4, REAGENT_ID_THIRTEENLOKO = 20, REAGENT_ID_HYPERZINE = 10),
	list(REAGENT_ID_ANTITOXIN = 2, REAGENT_ID_TRICORDRAZINE = 2),
	list(REAGENT_ID_DEXALINP = 2, REAGENT_ID_TRICORDRAZINE = 2),
	list(REAGENT_ID_BICARIDINE = 2, REAGENT_ID_TRICORDRAZINE = 2, REAGENT_ID_KELOTANE = 2)))

/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/slice_contents()
	var/list/recipes = TYPE_TABLE_GET(src, chaos_slice_recipes)
	return (slice_kind >= 1 && slice_kind <= length(recipes)) ? recipes[slice_kind] : null

/// Its icon follows the slice it rolled.
/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/roll_slice_icon(datum/roller/R)
	return "chaoscake_slice-[slice_kind]"

/// Per slice: name, description, taste and bite size.
TYPE_TABLE_DECLARE(/obj/item/reagent_containers/food/snacks/chaoscakeslice, chaos_slice_facts, list(
	list("Slice Of Evil", "An odd slice, despite the grease and cherries oozing off the top, it smells delicious.", list("The desire to consume" = 10), 7), // Pretty damn poisonous, takes a lot of work to make safe for consumption, useful for medical. You won't even taste the poison.
	list("Slice Of Evil", "A mysterious slice, coated in purple frosting that smells like grapes.", list("The desire to show off an party" = 10), 30), // A bad trip; even a single bite won't make you escape fate.
	list("Slice Of Evil", "A menacing slice, smelling clearly of copper, blood clots float on top.", list("Infernal Rage" = 10), 30), // acidic
	list("Slice Of Good", "A colourful slice, smelling of pear and coated in delicious cream.", list("Hapiness" = 10), 3), // anti-tox
	list("Slice Of Good", "A light slice, it's pretty to look at and smells of vanilla.", list("Freedom" = 10), 3), // anti-oxy
	list("Slice Of Good", "A hearty slice, it smells of chocolate and strawberries.", list("Love" = 10), 4))) // anti-burn/brute

/// One fact of the slice it rolled (chaos_slice_facts: 1 name, 2 description, 3 taste, 4 bite size).
/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/slice_fact(index)
	var/list/facts = TYPE_TABLE_GET(src, chaos_slice_facts)
	return (slice_kind >= 1 && slice_kind <= length(facts)) ? facts[slice_kind][index] : null

/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/roll_slice_name(datum/roller/R)
	return slice_fact(1)

/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/roll_slice_desc(datum/roller/R)
	return slice_fact(2)

/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/slice_taste()
	return slice_fact(3)

/obj/item/reagent_containers/food/snacks/chaoscakeslice/proc/roll_slice_bitesize(datum/roller/R)
	return slice_fact(4)

CAPABILITIES(/obj/structure/chaoscake)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/chaoscake/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/material/knife))
		if(edible == 1)
			HasSliceMissing()
			if(slices <= 0)
				to_chat(user, span_notice("The cake hums away quietly as the chaos powered goodness slowly recovers the large amount of lost mass, best to give it a moment before cutting another slice."))
				return OP_PASS
			else
				to_chat(user, span_notice("You cut a slice of the cake. The slice looks like the cake was just baked, and you can see before your eyes as the spot where you cut the slice slowly regenerates!"))
				slices = slices - 1
				set_icon_state("chaoscake-[slices]")
				new /obj/item/reagent_containers/food/snacks/chaoscakeslice(src.loc)

		else
			to_chat(user, span_notice("It looks so good... But it feels so wrong to eat it before it's finished..."))
			return OP_PASS
	if(istype(W,/obj/item/chaoscake_layer))
		var/obj/item/chaoscake_layer/C = W
		if(C.layer_stage == 8)
			to_chat(user, span_notice("Finally! The coin on the top, the almighty chaos cake is complete!"))
			consume(W, user)
			stage++
			desc = desclist2[stage]
			set_icon_state("chaoscake-6")
			edible = 1
			name = "The Chaos Cake!"
		else if(stage == maxstages)
			to_chat(user, span_warning("The cake is already done!"))
		else if(stage == C.layer_stage)
			to_chat(user, span_notice("You add another layer to the cake, nice."))
			consume(W, user)
			stage++
			desc = desclist2[stage]
			set_icon_state("chaoscake_stage-[stage]")
		else
			to_chat(user, span_warning("Hmm, doesnt seem like this layer is supposed to be added there?"))
	return OP_PASS

// The One Pizza

/obj/structure/theonepizza
	name = "The One Pizza"
	desc = "...it's real."

	icon = 'icons/obj/food64x64.dmi'
	icon_state = "theonepizza"
	pixel_x = -16
	pixel_y = -16

	var/slicetime = 15 SECONDS

	var/slicelist = list(/obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita/bigslice,
							/obj/item/reagent_containers/food/snacks/sliceable/pizza/pineapple/bigslice,
							/obj/item/reagent_containers/food/snacks/sliceable/pizza/meatpizza/bigslice,
							/obj/item/reagent_containers/food/snacks/sliceable/pizza/mushroompizza/bigslice,
							/obj/item/reagent_containers/food/snacks/sliceable/pizza/vegetablepizza/bigslice)

/obj/structure/theonepizza/proc/slice_done(datum/act/op/A)
	var/mob/living/user = A.actor
	act_message(user, null, MSG_SELF(span_notice("You successfully cut The One Pizza.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " successfully cuts The One Pizza.")))
	for(var/slicetype in slicelist)
		new slicetype(src.loc)
	consume(src, user)

MSG_DEF(theonepizza/slicing, span_notice("You start to slowly cut through The One Pizza."), span_bold("%U%") + " starts to slowly cut through The One Pizza.")

CAPABILITIES(/obj/structure/theonepizza)
	op("item", item(/obj/item/material/knife), label("Use"), begins(MSG(theonepizza/slicing)), wait(PROC_REF(slice_time)), then(PROC_REF(slice_done)))

/// How long the knife takes through it.
/obj/structure/theonepizza/proc/slice_time(datum/act/op/A)
	return slicetime

/obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita/bigslice
	name = "Giant Margherita slice"
	desc = "Big enough to be a sign at a pizzeria."
	icon_state = "big_cheese_slice"

/obj/item/reagent_containers/food/snacks/sliceable/pizza/pineapple/bigslice
	name = "Giant ham & pineapple pizza slice"
	desc = "This thing probably constitutes an italian warcrime."
	icon_state = "big_pineapple_slice"

/obj/item/reagent_containers/food/snacks/sliceable/pizza/meatpizza/bigslice
	name = "Giant meatpizza slice"
	desc = "A Meat Feast fit for a king."
	icon_state = "big_meat_slice"

/obj/item/reagent_containers/food/snacks/sliceable/pizza/mushroompizza/bigslice
	name = "Giant mushroompizza slice"
	desc = "Practically a honey mushroom at this scale."
	icon_state = "big_mushroom_slice"

/obj/item/reagent_containers/food/snacks/sliceable/pizza/vegetablepizza/bigslice
	name = "Giant vegetable pizza slice"
	desc = "So healthy it'll give you a heart attack."
	icon_state = "big_veggie_slice"

/transformation/kitchen/theonepizza
CAPABILITIES(/transformation/kitchen/theonepizza)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/meat, 1),
			item_term(/obj/item/reagent_containers/food/snacks/pineapple_ring, 1),
			item_term(/obj/item/reagent_containers/food/snacks/pineapple_ring, 1),
			fruit_term(PLANT_TOMATO, 5),
			fruit_term(PLANT_MUSHROOMS, 5),
			fruit_term(PLANT_EGGPLANT, 1),
			fruit_term(PLANT_CARROT, 1),
			fruit_term(PLANT_CORN, 1)),
		makes = list(item_term(/obj/structure/theonepizza, 1))))
