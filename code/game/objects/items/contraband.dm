// Let's get some REAL contraband stuff in here. Because come on, getting brigged for LIPSTICK is no fun.
//
// Includes drug powder.
//
// Illicit drugs~
/obj/item/storage/pill_bottle/happy
	name = "bottle of Happy pills"
	desc = "Highly illegal drug. When you want to see the rainbow."
	wrapper_color = COLOR_PINK
	starts_with = list(/obj/item/reagent_containers/pill/happy = 7)

/obj/item/storage/pill_bottle/zoom
	name = "bottle of Zoom pills"
	desc = "Highly illegal drug. Trade brain for speed."
	wrapper_color = COLOR_BLUE
	starts_with = list(/obj/item/reagent_containers/pill/zoom = 7)

/obj/item/reagent_containers/glass/beaker/vial/random
	flags = NONE
	var/list/random_reagent_list = list(list(REAGENT_ID_WATER = 15) = 1, list(REAGENT_ID_CLEANER = 15) = 1)

/obj/item/reagent_containers/glass/beaker/vial/random/toxin
	random_reagent_list = list(
		list(REAGENT_ID_MINDBREAKER = 10, REAGENT_ID_BLISS = 20)	= 3,
		list(REAGENT_ID_CARPOTOXIN = 15)							= 2,
		list(REAGENT_ID_IMPEDREZENE = 15)						= 2,
		list(REAGENT_ID_ZOMBIEPOWDER = 10)						= 1)

/obj/item/reagent_containers/glass/beaker/vial/random/Initialize(mapload)
	. = ..()
	if(is_open_container())
		flags ^= OPENCONTAINER

	var/list/picked_reagents = pickweight(random_reagent_list)
	for(var/reagent in picked_reagents)
		reagents.add_reagent(reagent, picked_reagents[reagent])

	var/list/names = list()
	for(var/datum/reagent/R in reagents.reagent_list)
		names += R.name

	desc = "Contains [english_list(names)]."
	update_icon()

//
// Drug Powder
//
/obj/item/reagent_containers/powder
	name = "powder"
	desc = "A powdered form of... something."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "powder"
	item_state = "powder"
	amount_per_transfer_from_this = 2
	max_transfer_amount = 2
	min_transfer_amount = 1
	w_class = ITEMSIZE_TINY
	volume = 50

/obj/item/reagent_containers/powder/examine(mob/user)
	if(reagents)
		var/datum/reagent/R = reagents.get_master_reagent()
		desc = "A powdered form of what appears to be [R.name]. There's about [reagents.total_volume] units here."
	return ..()

/obj/item/reagent_containers/powder/Initialize(mapload)
	. = ..()
	get_appearance()

/obj/item/reagent_containers/powder/proc/get_appearance()
	/// Names and colors based on dominant reagent.
	if (reagents.reagent_list.len > 0)
		color = reagents.get_color()
		var/datum/reagent/R = reagents.get_master_reagent()
		var/new_name = lowertext(R)
		name = "powdered [new_name]"

/// Snorting.

/obj/item/reagent_containers/powder/attackby(obj/item/W, mob/living/user)

	if(!ishuman(user)) /// You gotta be fleshy to snort the naughty drugs.
		return ..()

	if(!istype(W, /obj/item/glass_extra/straw) && !istype(W, /obj/item/reagent_containers/rollingpaper))
		return ..()

	user.visible_message(span_warning("[user] snorts [src] with [W]!"))
	playsound(loc, 'sound/effects/snort.ogg', 50, 1)

	if(reagents)
		reagents.trans_to_mob(user, amount_per_transfer_from_this, CHEM_BLOOD)

	if(!reagents.total_volume) /// Did we use all of it?
		qdel(src)

////// End powder. /////////


// === merged from contraband_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/stolenpackage
	name = "stolen package"
	desc = "What's in the box?"
	icon = 'icons/obj/storage.dmi'
	icon_state = "deliverycrate5"
	item_state = "table_parts"
	w_class = ITEMSIZE_HUGE

/obj/item/stolenpackage/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	// Another way of doing this. Commented out because the other method is better for this application.
	/*var/spawn_chance = rand(1,100)
	switch(spawn_chance)
		if(0 to 49)
			new /obj/random/gun/guarenteed(user.loc)
			to_chat(user, "You got a thing!")
		if(50 to 99)
			new /obj/item/bikehorn/rubberducky(user.loc)
			new /obj/item/bikehorn(user.loc)
			to_chat(user, "You got two things!")
		if(100)
			to_chat(user, "The box contained nothing!")
			return
	*/
	var/loot = pick(/obj/effect/landmark/costume,
					/obj/item/clothing/glasses/thermal,
					/obj/item/clothing/gloves/combat,
					/obj/item/clothing/head/bearpelt,
					/obj/item/clothing/mask/balaclava,
					/obj/item/clothing/mask/horsehead,
					/obj/item/clothing/mask/muzzle,
					/obj/item/clothing/suit/armor/heavy,
					/obj/item/clothing/suit/armor/laserproof,
					/obj/item/clothing/suit/armor/vest,
					/obj/item/chameleon,
					/obj/item/pda/clown,
					/obj/item/pda/mime,
					/obj/item/pda/syndicate,
					/obj/item/mecha_parts/chassis/phazon,
					/obj/item/mecha_parts/part/phazon_head,
					/obj/item/mecha_parts/part/phazon_left_arm,
					/obj/item/mecha_parts/part/phazon_left_leg,
					/obj/item/mecha_parts/part/phazon_right_arm,
					/obj/item/mecha_parts/part/phazon_right_leg,
					/obj/item/mecha_parts/part/phazon_torso,
					/obj/item/circuitboard/mecha/phazon/targeting,
					/obj/item/circuitboard/mecha/phazon/peripherals,
					/obj/item/circuitboard/mecha/phazon/main,
					/obj/item/bodysnatcher,
					/obj/item/bluespace_harpoon,
					/obj/item/clothing/accessory/permit/gun,
					/obj/item/perfect_tele,
					/obj/item/sleevemate,
					/obj/item/disk/nifsoft/compliance,
					/obj/item/implanter/compliance,
					/obj/item/seeds/ambrosiadeusseed,
					/obj/item/seeds/ambrosiavulgarisseed,
					/obj/item/seeds/libertymycelium,
					/obj/fiftyspawner/platinum,
					/obj/item/toy/nanotrasenballoon,
					/obj/item/toy/syndicateballoon,
					/obj/item/aiModule/syndicate,
					/obj/item/book/manual/wiki/engineering_hacking,
					/obj/item/card/emag,
					/obj/item/card/emag_broken,
					/obj/item/card/id/syndicate,
					/obj/item/poster,
					/obj/item/disposable_teleporter,
					/obj/item/grenade/flashbang/clusterbang,
					/obj/item/grenade/flashbang/clusterbang,
					/obj/item/grenade/spawnergrenade/spesscarp,
					/obj/item/melee/energy/sword,
					/obj/item/melee/telebaton,
					/obj/item/pen/reagent/paralysis,
					/obj/item/pickaxe/diamonddrill,
					/obj/item/reagent_containers/food/drinks/bottle/pwine,
					/obj/item/reagent_containers/food/snacks/carpmeat,
					/obj/item/reagent_containers/food/snacks/clownstears,
					/obj/item/reagent_containers/food/snacks/xenomeat,
					/obj/item/reagent_containers/glass/beaker/neurotoxin,
					/obj/item/rig/combat,
					/obj/item/shield/energy,
					/obj/item/stamp/centcomm,
					/obj/item/stamp/solgov,
					/obj/item/storage/fancy/cigar/havana,
					/obj/item/xenos_claw,
					/obj/random/contraband,
					/obj/random/contraband,
					/obj/random/contraband,
					/obj/random/contraband,
					/obj/random/weapon/guarenteed)
	//VOREstation edit - Randomized map objects were put in loot piles, so handle them...
	if(istype(loot,/obj/random))
		var/obj/random/randy = loot
		var/new_I = randy.spawn_item()
		qdel(loot)
		loot = new_I // swap it
	//VOREstation edit end
	new loot(user.loc)
	to_chat(user, "You unwrap the package.")
	qdel(src)

/obj/item/miscdisc
	name = "strange artefact"
	desc = "A large disc-shaped item, with a red, opaque crystal embedded in the center. It is some what heavy. There are indentations along the ring of the disc. Alien scripture lines the disc."
	icon_state = "wahdisc"
	icon = 'icons/obj/contraband_vr.dmi'
	w_class = ITEMSIZE_NORMAL

/obj/item/miscdisc/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	to_chat(user, "As you hold the large disc in your open palm, fingers cusped around the edge, the crystal embedded in the item begins to vibrate. It lifts itself from the disc a few cenimetres, before beginning to glow with a bright red light. The glow lasts for a few seconds, before the crystal embeds itself back into the disc with a quick snap.")


// === merged from contraband_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/contraband
	name = "contraband"
	desc = "A tightly sealed package. Dare to look inside?"
	icon = 'icons/obj/storage.dmi'
	icon_state = "deliverycrate5"
	item_state = "table_parts"
	w_class = ITEMSIZE_HUGE

/obj/item/contraband/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/contraband = pick(
		/obj/item/reagent_containers/glass/beaker/vial/macrocillin,
		/obj/item/reagent_containers/glass/beaker/vial/microcillin,
		/obj/item/gun/energy/sizegun/not_advanced,
		/obj/item/clothing/mask/muzzle,
		/obj/item/pda/clown,
		/obj/item/pda/mime,
		/obj/item/storage/fancy/cigar/havana,
		/obj/item/card/emag_broken,
		/obj/item/sleevemate,
		/obj/item/disk/nifsoft/compliance,
		/obj/item/seeds/ambrosiadeusseed,
		/obj/item/seeds/ambrosiavulgarisseed,
		/obj/item/bodysnatcher)

	user.put_in_hands(new contraband(usr.loc))
	to_chat(user, "You unwrap the package.")
	qdel(src)
