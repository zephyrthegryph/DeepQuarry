// future to do list for anyone who wants to try:
//Make building turf enterable for small people.
//Make buildings enterable then bustable from the inside.
//Tiny cars drivable only by small people, wheel chair code.
//Add details to planet foods as well as diversify options for cargo ordering.
//make water turfs stomp and apply to player sprites.

//turf items


//Used to make smole objects be able to be built from menu

/datum/material/smolebricks/generate_recipes()
	var/list/recipes = list(
		new/datum/stack_recipe("road straight", /obj/structure/smoletrack/roadS, 1, time = 5),
		new/datum/stack_recipe("road threeway", /obj/structure/smoletrack/roadT, 1, time = 5),
		new/datum/stack_recipe("road turn ", /obj/structure/smoletrack/roadturn, 1, time = 5),
		new/datum/stack_recipe("road fourway", /obj/structure/smoletrack/roadF, 1, time = 5),
		new/datum/stack_recipe("smole houses", /obj/structure/smolebuilding/houses, 2, time = 10),
		new/datum/stack_recipe("smole business", /obj/structure/smolebuilding/business, 2, time = 10),
		new/datum/stack_recipe("smole warehouses", /obj/structure/smolebuilding/warehouses, 2, time = 10),
		new/datum/stack_recipe("smole museum", /obj/structure/smolebuilding/museum, 2, time = 10)
	)
	return recipes

/datum/material/smolebricks
	name = MAT_SMOLEBRICKS
	stack_type = /obj/item/stack/material/smolebricks
	icon_base = "solid"
	icon_reinf = "reinf_over"
	destruction_desc = "smashed"
	sheet_singular_name = "bag"
	sheet_plural_name = "bags"
	supply_conversion_value = 1 // The value of smollbricks are only going up! Buy now! Fill your house! THE PLASTIC BRICKS ARE WORTH YOUR CHILD'S COLLEGE MONEY!

//the actual materials

/obj/item/stack/material/smolebricks
	name = MAT_SMOLEBRICKS
	desc = "A collection of tiny colored bricks ready to be built into whatever you want."
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "smolematerial"
	drop_sound = SFX_ITEMS_DROP_SMOLEMATERIAL
	pickup_sound = SFX_ITEMS_PICKUP_PILLBOTTLE
	default_type = MAT_SMOLEBRICKS
	w_class = ITEMSIZE_SMALL

//smolebrick case to make for easy bricks.
/obj/item/storage/smolebrickcase
	name = "smolebrick case"
	desc = "You feel the power of imagination."
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "smolestorage"
	throw_speed = 1
	throw_range = 4
	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_SMALL * 7 // most code copied from toolbox
	use_sound = SFX_ITEMS_STORAGE_SMOLECASE
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	starts_with = list( /obj/item/stack/material/smolebricks,
	/obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks,
	/obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks,
	/obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks, /obj/item/stack/material/smolebricks
	)

CAPABILITIES(/obj/item/storage/smolebrickcase)
	configure(storage(max_size = ITEMSIZE_NORMAL))

//Track code
//defineing actions

/obj/structure/smoletrack
	icon = 'icons/vore/smoleworld_vr.dmi'
	color = "#ffffff"
	density = FALSE

/obj/structure/smoletrack/Initialize(mapload)
	. = ..()
	make_rotatable()

CAPABILITIES(/obj/structure/smoletrack)
	op("smoletrack_dismantle_hand", hand(), ungated(), stance(I_DISARM), priority(OP_PRIORITY_DEFAULT - 1), label("Take apart"), then(PROC_REF(smoletrack_dismantle_hand)))
	op("smoletrack_verb_color", menu(), label("Use Color Pieces"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/color/smole_paint, fields = list("default" = nameof(color)), step = "colour"), then(PROC_REF(smoletrack_verb_color)))
	op("smoletrack_verb_dismantle", menu(), label("Take Road Apart"), needs(req_adjacent(), req_capable()), then(PROC_REF(smoletrack_verb_dismantle)))

/// Old attack_hand, disarm: take the piece apart.
/obj/structure/smoletrack/proc/smoletrack_dismantle_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
		return OP_OK
	to_chat(user, span_notice("[src] was dismantaled into bricks."))
	play_sfx(src, SFX_ITEMS_SMOLESMALLBUILD, volume_channel = VOLUME_CHANNEL_MASTER)
	var/turf/simulated/floor/F = get_turf(src)
	if(istype(F))
		new /obj/item/stack/material/smolebricks(F)
	destroyed(src, user, "deconstructed")
	return OP_OK

/obj/structure/smoletrack/ghosts_can_use_rotate_verbs()
	return CONFIG_GET(flag/ghost_interaction)

//color roads
/// Old Use Color Pieces verb.
/obj/structure/smoletrack/proc/smoletrack_verb_color(datum/act/op/A)
	var/mob/user = A.actor
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
		return
	var/picked = A.step_value("colour")
	if(picked)
		color = picked

/// A smole road or building's colour. Re-checked on the answer: the painter is still next to it.
/datum/prompt/color/smole_paint
	title = "Paint Color"
	question = "Please select color."
	ask_flags = ASK_NEAR_SUBJECT
	timeout = 0

// probably redundant, allows for direct way to dismantal without knowing intents
/// Old Take Road Apart verb.
/obj/structure/smoletrack/proc/smoletrack_verb_dismantle(datum/act/op/A)
	var/mob/user = A.actor
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
		return
	play_sfx(src, SFX_ITEMS_SMOLESMALLBUILD, volume_channel = VOLUME_CHANNEL_MASTER)
	var/turf/simulated/floor/F = get_turf(src)
	if(istype(F))
		new /obj/item/stack/material/smolebricks(F)
	destroyed(src, user, "deconstructed")
	return

// Road pieces

/obj/structure/smoletrack/roadS
	name = "road straight piece"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "carstraight"
	desc = "A long set of tiny road."
	anchored = TRUE

/obj/structure/smoletrack/roadT
	name = "road threeway piece"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "carthreeway"
	desc = "A tiny threeway road piece."
	anchored = TRUE

/obj/structure/smoletrack/roadturn
	name = "road turn piece"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "carturn"
	desc = "A tiny turn road piece."
	anchored = TRUE

/obj/structure/smoletrack/roadF
	name = "road four-way piece"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "carfourway"
	desc = "A four-way road piece."
	anchored = TRUE

//buildings code
//Defining building actions
/obj/structure/smolebuilding
	icon = 'icons/vore/smoleworld_vr.dmi'
	density = TRUE
	anchored = TRUE
	color = "#ffffff"
	micro_target = TRUE	//Now micros can enter and navigate these things!!!
	max_integrity = 75 // Three stomps.

//makes it so buildings can be dismaintaled or GodZilla style attacked

/// Old attack_hand: dismantle (disarm), bang on (harm) or knock on the building.
/obj/structure/smolebuilding/proc/smolebuilding_knock(datum/act/op/A)
	return smolebuilding_hand(A.actor, I_HELP)

/obj/structure/smolebuilding/proc/smolebuilding_dismantle_hand(datum/act/op/A)
	return smolebuilding_hand(A.actor, I_DISARM)

/obj/structure/smolebuilding/proc/smolebuilding_bang_hand(datum/act/op/A)
	return smolebuilding_hand(A.actor, I_HURT)

/obj/structure/smolebuilding/proc/smolebuilding_hand(mob/user, stance)
	if(stance == I_DISARM)
		if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
			return OP_OK
		to_chat(user, span_notice("[src] was dismantaled into bricks."))
		play_sfx(src, SFX_ITEMS_SMOLESMALLBUILD, volume_channel = VOLUME_CHANNEL_MASTER)
		if(!isnull(loc))
			new /obj/item/stack/material/smolebricks(loc)
			new /obj/item/stack/material/smolebricks(loc)
		spent(src, user)

	else if (stance == I_HURT)

		if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
			return OP_OK
		play_sfx(src, SFX_ITEMS_SMOLEBUILDINGHIT2)
		user.do_attack_animation(src)
		act_message(user, src, MSG_SELF(span_danger("You bang against %T%!")), \
			MSG_OTHERS(span_danger("%U% bangs against %T%!")), \
			MSG_BLIND("You hear a banging sound."))
		take_damage(25, BRUTE, MELEE, FALSE)
	else
		act_message(user, null, MSG_SELF("You knock on the [src.name]."), MSG_OTHERS("[user.name] knocks on the [src.name]."))
	return OP_OK

/// Stomped flat: the building leaves ruins.
/obj/structure/smolebuilding/handle_deconstruct(disassembled = TRUE)
	visible_message(span_danger("\The [src] falls apart!"))
	play_sfx(src, SFX_ITEMS_SMOLEBUILDINGDESTORYED, volume_channel = VOLUME_CHANNEL_MASTER)
	new /obj/structure/smoleruins(loc)
//results of attacks will remove building and spawn in ruins.
/obj/structure/smolebuilding/proc/dismantle()
	deconstruct(FALSE)

//checks for items and does the same as dismaintle but spawns material instead.
/// Old attackby: a harm-intent hit with an item flattens it; any other click with an item does nothing destructive.
/obj/structure/smolebuilding/proc/smolebuilding_item(datum/act/op/A)
	dismantle()
	return OP_OK
//checks for projectile damage and does the same as dismaintle but spawns material instead.
CAPABILITIES(/obj/structure/smolebuilding)
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(smolebuilding_shot))))
	// Declared before the hand ops: a held item answers first, and a click not on harm intent is refused (never the bare-hand op).
	op("smolebuilding_item", item(/obj/item), answers(INTENT_ATTACK, INTENT_USE), needs(req(TYPE_PROC_REF(/atom, harm_click_only), because = MSG(harm_click_only))), priority(OP_PRIORITY_DEFAULT - 1), label("Smash"), then(PROC_REF(smolebuilding_item)))
	op("smolebuilding_knock_help", hand(), ungated(), stance(I_HELP), priority(OP_PRIORITY_DEFAULT - 1), label("Knock on"), then(PROC_REF(smolebuilding_knock)))
	op("smolebuilding_dismantle", hand(), ungated(), stance(I_DISARM), priority(OP_PRIORITY_DEFAULT - 1), label("Take apart"), then(PROC_REF(smolebuilding_dismantle_hand)))
	op("smolebuilding_knock_grab", hand(), ungated(), stance(I_GRAB), priority(OP_PRIORITY_DEFAULT - 1), label("Knock on"), then(PROC_REF(smolebuilding_knock)))
	op("smolebuilding_bang", hand(), ungated(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Bang on"), then(PROC_REF(smolebuilding_bang_hand)))
	op("smolebuilding_verb_color", menu(), label("Use Color Pieces"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/color/smole_paint, fields = list("default" = nameof(color)), step = "colour"), then(PROC_REF(smolebuilding_verb_color)))
	op("smolebuilding_verb_dismantle", menu(), label("Take Building Apart"), needs(req_adjacent(), req_capable()), then(PROC_REF(smolebuilding_verb_dismantle)))

/obj/structure/smolebuilding/proc/smolebuilding_shot(datum/act/hit/projectile/A)
	displode()
	return OP_OK
//is the same as dismaintal but instead of ruins it just makes it all explode
/obj/structure/smolebuilding/proc/displode()
	visible_message(span_danger("\The [src] explodes into pieces!"))
	play_sfx(src, SFX_ITEMS_SMOLEBUILDINGDESTORYEDSHORT, volume_channel = VOLUME_CHANNEL_MASTER)
	new /obj/item/stack/material/smolebricks(loc)
	replace_with(src, /obj/item/stack/material/smolebricks)
	return

//get material from ruins

/// Old attack_hand, disarm: take the ruins apart.
/obj/structure/smoleruins/proc/smoleruins_dismantle_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
		return OP_OK
	to_chat(user, span_notice("[src] was dismantaled into bricks."))
	play_sfx(src, SFX_ITEMS_SMOLELARGEUNBUILD, volume_channel = VOLUME_CHANNEL_MASTER)
	if(!isnull(loc))
		new /obj/item/stack/material/smolebricks(loc)
		new /obj/item/stack/material/smolebricks(loc)
	destroyed(src, user, "deconstructed")
	return OP_OK

//Ruins go asplode same as buildings if attacked
/// Old attackby: a harm-intent hit with an item blows the ruins apart.
/obj/structure/smoleruins/proc/smoleruins_item(datum/act/op/A)
	displode()
	return OP_OK

CAPABILITIES(/obj/structure/smoleruins)
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(smoleruins_shot))))
	op("smoleruins_item", item(/obj/item), answers(INTENT_ATTACK, INTENT_USE), needs(req(TYPE_PROC_REF(/atom, harm_click_only), because = MSG(harm_click_only))), priority(OP_PRIORITY_DEFAULT - 1), label("Smash"), then(PROC_REF(smoleruins_item)))
	op("smoleruins_dismantle_hand", hand(), ungated(), stance(I_DISARM), priority(OP_PRIORITY_DEFAULT - 1), label("Take apart"), then(PROC_REF(smoleruins_dismantle_hand)))

/// Ruins blow apart when shot, same as buildings.
/obj/structure/smoleruins/proc/smoleruins_shot(datum/act/hit/projectile/A)
	displode()
	return OP_OK

/obj/structure/smoleruins/proc/displode()
	visible_message(span_danger("\The [src] explodes into pieces!"))
	play_sfx(src, SFX_ITEMS_SMOLEBUILDINGDESTORYEDSHORT, volume_channel = VOLUME_CHANNEL_MASTER)
	new /obj/item/stack/material/smolebricks(loc)
	replace_with(src, /obj/item/stack/material/smolebricks)
	return

//color buildings
/// Old Use Color Pieces verb.
/obj/structure/smolebuilding/proc/smolebuilding_verb_color(datum/act/op/A)
	var/mob/user = A.actor
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
		return
	var/picked = A.step_value("colour")
	if(picked)
		color = picked

//probably a bit redundant but gives a more direct way to disassemble buildings without using intents
/// Old Take Building Apart verb.
/obj/structure/smolebuilding/proc/smolebuilding_verb_dismantle(datum/act/op/A)
	var/mob/user = A.actor
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user) && !CONFIG_GET(flag/ghost_interaction)))
		return
	play_sfx(src, SFX_ITEMS_SMOLESMALLBUILD, volume_channel = VOLUME_CHANNEL_MASTER)
	if(!isnull(loc))
		new /obj/item/stack/material/smolebricks(loc)
		new /obj/item/stack/material/smolebricks(loc)
	destroyed(src, user, "deconstructed")
	return

//buildings
/obj/structure/smoleruins
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "ruins"
	density = FALSE

/obj/structure/smolebuilding/houses
	name = "smole houses"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "smolehouses"
	color = "#ffffff"

/obj/structure/smolebuilding/business
	name = "smole business"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "smolebusiness"
	color = "#ffffff"

/obj/structure/smolebuilding/warehouses
	name = "smole warehouses"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "smolewarehouses"
	color = "#ffffff"

/obj/structure/smolebuilding/museum
	name = "smole museum"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "smolemuseum"
	color = "#ffffff"
//
//CAR STUFF < WILL BE MESSED WITH IN A LATER UPDATE COMMENTED OUT FOR NOW
///obj/item/smolecar
///obj/structure/smolecar
///obj/structure/bed/chair/wheelchair/smolecar/can_buckle_check(mob/living/M, forced = FALSE)
/obj/item/trash/candychunk
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_sugarchunk"
	name = "chunk of candy"
	desc = "A solid chunk of candy crumbs, looks like it could be messy."

/obj/item/trash/Asteroidlarge
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_asteriodA"
	name = "asteriod"
	desc = "A solid chunk of candy crumb that looks like a asteriod."

/obj/item/trash/Asteroidmulti
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_asteriodC"
	name = "asteriod"
	desc = "Several chunks of sugar crumbs that looks like asteriods."

/obj/item/bikehorn/tinytether
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "tether_trash"
	name = "tether"
	desc = "Its a tiny bit of plastic in the shape of the tether. There seems to be a small button on top."
	honk_sound = SFX_ITEMS_TINYTETHER

/obj/item/reagent_containers/food/snacks/snackplanet/moon
	name = "moon"
	desc = "A firm solid mass of white powdery sugar in the shape of a moon!"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_moon"
	bitesize = 1
	nutriment_amt = 2
	nutriment_desc = list(REAGENT_ID_SUGAR = 2)
	drop_sound = SFX_ITEMS_DROP_BASKETBALL

/obj/item/reagent_containers/food/snacks/snackplanet/virgo3b
	name = "Virgo 3B"
	desc = "A sticky jelly jaw breaker in the shape of Virgo-3B, it even has a tiny tether!"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_Virgo3B"
	bitesize = 3
	trash = /obj/item/bikehorn/tinytether
	nutriment_amt = 2
	nutriment_desc = list("spicy" = 2, "tang" = 2)
	drop_sound = SFX_ITEMS_DROP_BASKETBALL

/obj/item/reagent_containers/food/snacks/snackplanet/phoron
	name = "phoron giant"
	desc = "A spicy jaw breaker that seems to swirl in the light."
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_phoron"
	bitesize = 3
	trash = /obj/item/trash/candychunk
	nutriment_amt = 2
	nutriment_desc = list("spicy" = 2)
	drop_sound = SFX_ITEMS_DROP_BASKETBALL

/obj/item/reagent_containers/food/snacks/snackplanet/virgoprime
	name = "Virgo Prime"
	desc = "It's a orange jaw breaker in the shape of Virgo Prime!"
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_virgoprime"
	bitesize = 3
	trash = /obj/item/trash/candychunk
	nutriment_amt = 2
	nutriment_desc = list("salty" = 2)
	drop_sound = SFX_ITEMS_DROP_BASKETBALL

/obj/item/storage/bagoplanets
	name = "bag o' planets"
	desc = "A cosmic bag of fist-sized candy planets."
	icon = 'icons/vore/smoleworld_vr.dmi'
	icon_state = "sp_storage"
	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_SMALL * 7 // most code copied from toolbox
	drop_sound = SFX_ITEMS_DROP_FOOD
	pickup_sound = SFX_ITEMS_PICKUP_FOOD
	starts_with = list(/obj/item/reagent_containers/food/snacks/snackplanet/phoron,
	/obj/item/reagent_containers/food/snacks/snackplanet/virgo3b,/obj/item/reagent_containers/food/snacks/snackplanet/moon,
	/obj/item/reagent_containers/food/snacks/snackplanet/virgoprime
	)


CAPABILITIES(/obj/item/storage/bagoplanets)
	configure(storage(max_size = ITEMSIZE_NORMAL))
