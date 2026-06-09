
//Not to be confused with /obj/item/reagent_containers/food/drinks/bottle

/obj/item/reagent_containers/glass/bottle
	name = "bottle"
	desc = "A small bottle."
	icon = 'icons/obj/chemical.dmi'
	icon_state = null
	item_state = "atoxinbottle"
	amount_per_transfer_from_this = 10
	max_transfer_amount = 60
	flags = NONE
	volume = 60
	drop_sound = 'sound/items/drop/bottle.ogg'
	pickup_sound = 'sound/items/pickup/bottle.ogg'

/obj/item/reagent_containers/glass/bottle/on_reagent_change()
	update_icon()

/obj/item/reagent_containers/glass/bottle/pickup(mob/user)
	..()
	update_icon()

/obj/item/reagent_containers/glass/bottle/dropped(mob/user, equipping, slot)
	..()
	update_icon()

/obj/item/reagent_containers/glass/bottle/attack_hand()
	..()
	update_icon()

/obj/item/reagent_containers/glass/bottle/Initialize(mapload)
	. = ..()
	if(!icon_state)
		icon_state = "bottle-[rand(1,4)]"

/obj/item/reagent_containers/glass/bottle/update_icon()
	cut_overlays()

	if(reagents.total_volume)
		var/image/filling = image('icons/obj/reagentfillings.dmi', src, "[icon_state]10")

		var/percent = round((reagents.total_volume / volume) * 100)
		switch(percent)
			if(0.1 to 20)	filling.icon_state = "[icon_state]-10"
			if(20 to 40) 	filling.icon_state = "[icon_state]-20"
			if(40 to 60)	filling.icon_state = "[icon_state]-40"
			if(60 to 80)	filling.icon_state = "[icon_state]-60"
			if(80 to 100)	filling.icon_state = "[icon_state]-80"
			if(100 to INFINITY)	filling.icon_state = "[icon_state]-100"

		filling.color = reagents.get_color()
		add_overlay(filling)

	if (!is_open_container())
		add_overlay("lid_[icon_state]")

	if (label_text)
		add_overlay("label_[icon_state]")

/obj/item/reagent_containers/glass/bottle/inaprovaline
	name = "inaprovaline bottle"
	desc = "A small bottle. Contains inaprovaline - used to stabilize patients."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_INAPROVALINE = 60)

/obj/item/reagent_containers/glass/bottle/toxin
	name = "toxin bottle"
	desc = "A small bottle of toxins. Do not drink, it is poisonous."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_TOXIN = 60)

/obj/item/reagent_containers/glass/bottle/cyanide
	name = "cyanide bottle"
	desc = "A small bottle of cyanide. Bitter almonds?"
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_CYANIDE = 30) //volume changed to match chloral

/obj/item/reagent_containers/glass/bottle/stoxin
	name = "soporific bottle"
	desc = "A small bottle of soporific. Just the fumes make you sleepy."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_STOXIN = 60)

/obj/item/reagent_containers/glass/bottle/chloralhydrate
	name = "chloral hydrate bottle"
	desc = "A small bottle of Choral Hydrate. Mickey's Favorite!"
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_CHLORALHYDRATE = 30) //Intentionally low since it is so strong. Still enough to knock someone out.

/obj/item/reagent_containers/glass/bottle/antitoxin
	name = "dylovene bottle"
	desc = "A small bottle of dylovene. Counters poisons, and repairs damage. A wonder drug."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_ANTITOXIN = 60)

/obj/item/reagent_containers/glass/bottle/mutagen
	name = "unstable mutagen bottle"
	desc = "A small bottle of unstable mutagen. Randomly changes the DNA structure of whoever comes in contact."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_MUTAGEN = 60)

/obj/item/reagent_containers/glass/bottle/ammonia
	name = "ammonia bottle"
	desc = "A small bottle."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_AMMONIA = 60)

/obj/item/reagent_containers/glass/bottle/eznutrient
	name = "\improper EZ NUtrient bottle"
	desc = "A small bottle."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_EZNUTRIENT = 60)

/obj/item/reagent_containers/glass/bottle/left4zed
	name = "\improper Left-4-Zed bottle"
	desc = "A small bottle."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_LEFT4ZED = 60)

/obj/item/reagent_containers/glass/bottle/robustharvest
	name = "\improper Robust Harvest"
	desc = "A small bottle."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_ROBUSTHARVEST = 60)

/obj/item/reagent_containers/glass/bottle/diethylamine
	name = "diethylamine bottle"
	desc = "A small bottle."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_DIETHYLAMINE = 60)

/obj/item/reagent_containers/glass/bottle/pacid
	name = "polytrinic acid bottle"
	desc = "A small bottle. Contains a small amount of Polytrinic Acid"
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_PACID = 60)

/obj/item/reagent_containers/glass/bottle/adminordrazine
	name = "adminordrazine bottle"
	desc = "A small bottle. Contains the liquid essence of the gods."
	icon = 'icons/obj/drinks.dmi'
	icon_state = "holyflask"
	prefill = list(REAGENT_ID_ADMINORDRAZINE = 60)

/obj/item/reagent_containers/glass/bottle/capsaicin
	name = "capsaicin bottle"
	desc = "A small bottle. Contains hot sauce."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_CAPSAICIN = 60)

/obj/item/reagent_containers/glass/bottle/frostoil
	name = "frost oil bottle"
	desc = "A small bottle. Contains cold sauce."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_FROSTOIL = 60)

/obj/item/reagent_containers/glass/bottle/biomass
	name = "biomass bottle"
	desc = "A bottle of raw biomass! Gross!"
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_BIOMASS = 60)

/obj/item/reagent_containers/glass/bottle/cakebatter
	name = "cake batter bottle"
	desc = "A bottle of pre-made cake batter."
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_CAKEBATTER = 60)

/obj/item/reagent_containers/glass/bottle/cinnamonpowder
	name = "cinnamon powder bottle"
	desc = "A bottle with expensive cinnamon powder."
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_CINNAMONPOWDER = 30) // Expensive!

/obj/item/reagent_containers/glass/bottle/nothing
	name = "empty bottle?"
	desc = "An apparently empty bottle."
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_NOTHING = 60)

/obj/item/reagent_containers/glass/bottle/gelatin
	name = "gelatin bottle"
	desc = "A bottle full of gelatin."
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_GELATIN = 60)

/obj/item/reagent_containers/glass/bottle/lube
	name = "lube bottle"
	desc = "A bottle full of lube."
	icon_state = "bottle-1"
	prefill = list(REAGENT_ID_LUBE = 60)


// === merged from bottle_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/reagent_containers/glass/bottle/sorbitol
	name = "sorbitol bottle"
	desc = "A small bottle of sorbitol. Sickeningly sweet."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_SORBITOL = 60)


// === merged from bottle_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/reagent_containers/glass/bottle/bicaridine
	name = "bicaridine bottle"
	desc = "A small bottle. Bicaridine is an analgesic medication and can be used to treat blunt trauma."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_BICARIDINE = 60)

/obj/item/reagent_containers/glass/bottle/vermicetol
	name = "vermicetol bottle"
	desc = "A small bottle. Vermicetol is an powerful analgesic medication and can be used to treat blunt trauma."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_VERMICETOL = 60)

/obj/item/reagent_containers/glass/bottle/keloderm
	name = "keloderm bottle"
	desc = "A small bottle. A fifty-fifty mix of the popular burn medications kelotane and deramline."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_DERMALINE = 30, REAGENT_ID_KELOTANE = 30)

/obj/item/reagent_containers/glass/bottle/dermaline
	name = "dermaline bottle"
	desc = "A small bottle. Dermaline is the next step in burn medication. Works twice as good as kelotane and enables the body to restore even the direst heat-damaged tissue."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_DERMALINE = 60)

/obj/item/reagent_containers/glass/bottle/carthatoline
	name = "carthatoline bottle"
	desc = "A small bottle. Carthatoline is strong evacuant used to treat severe poisoning."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_CARTHATOLINE = 60)

/obj/item/reagent_containers/glass/bottle/dexalinp
	name = "dexalinp bottle"
	desc = "A small bottle. Dexalin Plus is used in the treatment of oxygen deprivation. It is highly effective."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_DEXALINP = 60)

/obj/item/reagent_containers/glass/bottle/tramadol
	name = "tramadol bottle"
	desc = "A small bottle. A simple, yet effective painkiller."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_TRAMADOL = 60)

/obj/item/reagent_containers/glass/bottle/oxycodone
	name = "oxycodone bottle"
	desc = "A small bottle. An effective and very addictive painkiller."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_OXYCODONE = 60)

/obj/item/reagent_containers/glass/bottle/alkysine
	name = "alkysine bottle"
	desc = "A small bottle. Alkysine is a drug used to lessen the damage to neurological tissue after a catastrophic injury. Can heal brain tissue."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_ALKYSINE = 60)

/obj/item/reagent_containers/glass/bottle/imidazoline
	name = "imidazoline bottle"
	desc = "A small bottle. Heals eye damage."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_IMIDAZOLINE = 60)

/obj/item/reagent_containers/glass/bottle/peridaxon
	name = "peridaxon bottle"
	desc = "A small bottle. Used to encourage recovery of internal organs and nervous systems. Medicate cautiously."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_PERIDAXON = 60)

/obj/item/reagent_containers/glass/bottle/osteodaxon
	name = "osteodaxon bottle"
	desc = "A small bottle. An experimental drug used to heal bone fractures."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_OSTEODAXON = 60)

/obj/item/reagent_containers/glass/bottle/myelamine
	name = "myelamine bottle"
	desc = "A small bottle. Used to rapidly clot internal hemorrhages by increasing the effectiveness of platelets."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_MYELAMINE = 60)

/obj/item/reagent_containers/glass/bottle/hyronalin
	name = "hyronalin bottle"
	desc = "A small bottle. Hyronalin is a medicinal drug used to counter the effect of radiation poisoning."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_HYRONALIN = 60)

/obj/item/reagent_containers/glass/bottle/arithrazine
	name = "arithrazine bottle"
	desc = "A small bottle. Arithrazine is an unstable medication used for the most extreme cases of radiation poisoning."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_ARITHRAZINE = 60)

/obj/item/reagent_containers/glass/bottle/spaceacillin
	name = "spaceacillin bottle"
	desc = "A small bottle. An all-purpose antiviral agent."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_SPACEACILLIN = 60)

/obj/item/reagent_containers/glass/bottle/corophizine
	name = "corophizine bottle"
	desc = "A small bottle. A wide-spectrum antibiotic drug. Powerful and uncomfortable in equal doses."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_COROPHIZINE = 60)

/obj/item/reagent_containers/glass/bottle/rezadone
	name = "rezadone bottle"
	desc = "A small bottle. A powder with almost magical properties, this substance can effectively treat genetic damage in humanoids, though excessive consumption has side effects."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_REZADONE = 60)

/obj/item/reagent_containers/glass/bottle/healing_nanites
	name = "healing nanites bottle"
	desc = "A small bottle. Miniature medical robots that swiftly restore bodily damage."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-4"
	prefill = list(REAGENT_ID_HEALINGNANITES = 60)

/obj/item/reagent_containers/glass/bottle/ickypak
	name = "ickypak bottle"
	desc = "A small bottle of ickypak. The smell alone makes you gag."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_ICKYPAK = 60)

/obj/item/reagent_containers/glass/bottle/unsorbitol
	name = "unsorbitol bottle"
	desc = "A small bottle of unsorbitol. Sickeningly sweet."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"
	prefill = list(REAGENT_ID_UNSORBITOL = 60)

/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/glucose
	name = "glucose container"
	desc = "A container of glucose. Used to treat bloodloss through a hardsuit in unconscious patients."

/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/glucose/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_GLUCOSE, 100)
	on_reagent_change()
