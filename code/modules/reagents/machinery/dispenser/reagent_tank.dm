/obj/structure/reagent_dispensers
	name = "Dispenser"
	desc = "..."
	icon = 'icons/obj/chemical_tanks.dmi'
	icon_state = "tank"
	layer = TABLE_LAYER
	density = TRUE
	anchored = FALSE
	pressure_resistance = 2*ONE_ATMOSPHERE

	var/has_sockets = TRUE

	var/amount_per_transfer_from_this = 10
	var/possible_transfer_amounts = list(10,25,50,100)

	var/open_top = FALSE

/// What one transfer from the tank moves: its own setting (a container with a tap draws that much).
/obj/structure/reagent_dispensers/legacy_transfer_amount()
	return amount_per_transfer_from_this

/// Requirement: the dispenser offers transfer amounts (the old Initialize dropped the set_APTFT verb without them).
/obj/structure/reagent_dispensers/proc/has_transfer_amounts(datum/act/op/A)
	return !!possible_transfer_amounts // ALLOW(reads): the amounts are a type constant no code changes at run time

/// Old attackby: an item is not used on the tank itself; the click goes on (a container fills from the tank in its own afterattack).
/obj/structure/reagent_dispensers/proc/interaction_item(datum/act/op/A)
	return OP_PASS

/// The tank's reagents: 5000 units (reagents() in its CAPABILITIES block); each kind of tank adds to or replaces the contents with configure(reagents(add = | starts =)).

/obj/structure/reagent_dispensers/Initialize(mapload)
	. = ..()
	if(has_sockets)
		add_hose_connector(/datum/hose_connector/input)
		add_hose_connector(/datum/hose_connector/output)

/obj/structure/reagent_dispensers/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += span_notice("It contains:")
		if(reagents && reagents.reagent_list.len)
			for(var/datum/reagent/R in reagents.reagent_list)
				. += span_notice("[R.volume] units of [R.name]")
		else
			. += span_notice("Nothing.")

/// Old verb "Set transfer amount": set amount_per_transfer_from_this.
/obj/structure/reagent_dispensers/proc/reagent_dispenser_set_aptft(datum/act/op/A)
	var/N = A.step_value("a1")
	if (N)
		amount_per_transfer_from_this = N

/obj/structure/reagent_dispensers/proc/reagent_dispenser_set_aptft_a1_title(datum/act/op/A)
	return "[src]"

CAPABILITIES(/obj/structure/reagent_dispensers)
	reagents(5000)
	op("interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT), then(PROC_REF(interaction_item)))
	extend("melee_hit", when(cond_not(req(/obj/item/reagent_containers)))) // a container click on a tank taps it, hostile or not, instead of hitting it
	op("interaction_alt", hand(), ungated(), gesture(GESTURE_ALT), then(PROC_REF(interaction_alt)))
	op("reagent_dispenser_set_aptft", menu(), label("Set transfer amount"), when(PROC_REF(has_transfer_amounts)), asks(/datum/prompt/choice, fields = list("question" = "Amount per transfer from this:", "title" = computed(PROC_REF(reagent_dispenser_set_aptft_a1_title)), "choices" = nameof(possible_transfer_amounts), "timeout" = 0), step = "a1"), then(PROC_REF(reagent_dispenser_set_aptft)))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(dispenser_blob_burst))))

/// A blob bursts the tank outright.
/obj/structure/reagent_dispensers/proc/dispenser_blob_burst(datum/act/hit/blob/A)
	destroyed(src, null, "explosion")
	return TRUE

/// Old click_alt.
/obj/structure/reagent_dispensers/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(!Adjacent(user))
		return TRUE

	if(flags & OPENCONTAINER)
		to_chat(user, span_notice("You close the input on \the [src]"))
		flags -= OPENCONTAINER
		open_top = FALSE
	else
		to_chat(user, span_notice("You open the input on \the [src], allowing you to pour reagents in."))
		flags |= OPENCONTAINER
		open_top = TRUE
	return TRUE

/*
 * Tanks
 */

//Water
/obj/structure/reagent_dispensers/watertank
	name = "water tank"
	desc = "A water tank."
	icon_state = "water"
	amount_per_transfer_from_this = 10


CAPABILITIES(/obj/structure/reagent_dispensers/watertank)
	configure(reagents(add = list(REAGENT_ID_WATER = 1000)))
	climb()
	op("watertank_interaction_item", item(/obj/item), then(PROC_REF(watertank_interaction_item)))

/obj/structure/reagent_dispensers/watertank/high
	name = "high-capacity water tank"
	desc = "A highly-pressurized water tank made to hold vast amounts of water.."
	icon_state = "water_high"

CAPABILITIES(/obj/structure/reagent_dispensers/watertank/high)
	configure(reagents(add = list(REAGENT_ID_WATER = 4000)))

/obj/structure/reagent_dispensers/watertank/barrel
	name = "water barrel"
	desc = "A barrel for holding water."
	icon_state = "waterbarrel"

//Fuel
/obj/structure/reagent_dispensers/fueltank
	name = "fuel tank"
	desc = "A fuel tank."
	icon_state = REAGENT_ID_FUEL
	amount_per_transfer_from_this = 10
	var/modded = 0
	var/obj/item/assembly_holder/rig = null


CAPABILITIES(/obj/structure/reagent_dispensers/fueltank)
	owns_one(nameof(rig), /obj/item/assembly_holder)
	configure(reagents(add = list(REAGENT_ID_FUEL = 1000)))
	climb()
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(tank_blast_explode))))
	op("hand", hand(), label("Use"), ungated(), when(PROC_REF(has_rig)), begins(MSG(fueltank/detaching)), wait(2 SECONDS), then(PROC_REF(detach_rig_done)))
	op("fueltank_interaction_item", item(/obj/item/assembly_holder), needs(req_bool(PROC_REF(no_rig), because = MSG(fueltank/in_the_way))),
		begins(MSG(fueltank/rigging)), wait(2 SECONDS), then(PROC_REF(rig_assembly_done)))

/obj/structure/reagent_dispensers/fueltank/high
	name = "high-capacity fuel tank"
	desc = "A highly-pressurized fuel tank made to hold vast amounts of fuel."
	icon_state = "fuel_high"

CAPABILITIES(/obj/structure/reagent_dispensers/fueltank/high)
	configure(reagents(starts = list(REAGENT_ID_FUEL = 4000)))

//Foam
/obj/structure/reagent_dispensers/foam
	name = "foam tank"
	desc = "A foam tank."
	icon_state = "foam"
	amount_per_transfer_from_this = 10


CAPABILITIES(/obj/structure/reagent_dispensers/foam)
	configure(reagents(starts = list(REAGENT_ID_FIREFOAM = 1000)))
	climb()

//Helium3
/obj/structure/reagent_dispensers/he3
	name = "He3 tank"
	desc = "A Helium3 tank."
	icon_state = "he3"
	amount_per_transfer_from_this = 10


CAPABILITIES(/obj/structure/reagent_dispensers/he3)
	configure(reagents(starts = list(REAGENT_ID_HELIUM3 = 1000)))
	climb()

/*
 * Misc
 */

/obj/structure/reagent_dispensers/fueltank/barrel
	name = "hazardous barrel"
	desc = "An open-topped barrel full of nasty-looking liquid."
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "barrel"
	modded = TRUE

/obj/structure/reagent_dispensers/fueltank/barrel/two
	name = "explosive barrel"
	desc = "A barrel with warning labels painted all over it."
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "barrel2"
	modded = FALSE

/obj/structure/reagent_dispensers/fueltank/barrel/three
	name = "fuel barrel"
	desc = "An open-topped barrel full of nasty-looking liquid."
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "barrel3"
	modded = FALSE

/obj/structure/reagent_dispensers/fueltank/barrel/wrench_act(mob/user, obj/item/tool)
	return ITEM_INTERACT_BLOCKING // Open barrels have no closable faucet.

/obj/structure/reagent_dispensers/fueltank/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		if(modded)
			. += span_warning("Fuel faucet is wrenched open, leaking the fuel!")
		if(rig)
			. += span_notice("There is some kind of device rigged to the tank.")

MSG_DEF(fueltank/detaching, "You begin to detach the device from %T%.", "%U% begins to detach the device from %T%.")
MSG_DEF(fueltank/rigging, "You begin rigging %I% to %T%.", "%U% begins rigging %I% to %T%.")
MSG_DEF_SELF(fueltank/in_the_way, span_warning("There is another device in the way."))

/// Something is rigged to the tank.
/obj/structure/reagent_dispensers/fueltank/proc/has_rig(datum/act/op/A)
	return !!rig

/// Requirement: nothing is rigged to the tank yet.
/obj/structure/reagent_dispensers/fueltank/proc/no_rig(datum/act/op/A)
	return !rig

/obj/structure/reagent_dispensers/fueltank/proc/detach_rig_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!rig)
		return
	act_message(user, src, MSG_SELF(span_notice("You detach [rig] from %T%")), MSG_OTHERS(span_notice("%U% detaches [rig] from %T%.")))
	rig.forceMove(get_turf(user))
	rel_take(src, nameof(rig))
	overlays = new/list()

/obj/structure/reagent_dispensers/fueltank/proc/rig_assembly_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/assembly_holder/H = A.held
	add_fingerprint(user)
	if(rig)
		return
	act_message(user, src, MSG_SELF(span_notice("You rig [H] to %T%")), MSG_OTHERS(span_notice("%U% rigs [H] to %T%.")))

	if (istype(H.a_left,/obj/item/assembly/igniter) || istype(H.a_right,/obj/item/assembly/igniter))
		message_admins("[key_name_admin(user)] rigged fueltank at [loc.loc.name] ([loc.x],[loc.y],[loc.z]) for explosion. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[loc.x];Y=[loc.y];Z=[loc.z]'>JMP</a>)")
		log_game("[key_name(user)] rigged fueltank at [loc.loc.name] ([loc.x],[loc.y],[loc.z]) for explosion.")

	if(!move_into(src, nameof(src.rig), H, user))
		return

	var/icon/test = getFlatIcon(H)
	test.Shift(NORTH,1)
	test.Shift(EAST,6)
	add_overlay(test)

/obj/structure/reagent_dispensers/fueltank/wrench_act(mob/user, obj/item/tool)
	add_fingerprint(user)
	act_message(user, src, MSG_SELF("You wrench %T%'s faucet [modded ? "closed" : "open"]"), \
		MSG_OTHERS("%U% wrenches %T%'s faucet [modded ? "closed" : "open"]."))
	modded = !modded
	playsound(src, tool.usesound, 75, TRUE)
	if(modded)
		message_admins("[key_name_admin(user)] opened fueltank at [loc.loc.name] ([loc.x],[loc.y],[loc.z]), leaking fuel. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[loc.x];Y=[loc.y];Z=[loc.z]'>JMP</a>)")
		log_game("[key_name(user)] opened fueltank at [loc.loc.name] ([loc.x],[loc.y],[loc.z]), leaking fuel.")
		leak_fuel(amount_per_transfer_from_this)
	return ITEM_INTERACT_SUCCESS


/obj/structure/reagent_dispensers/fueltank/bullet_act(obj/item/projectile/Proj)
	if(Proj.get_structure_damage())
		if(istype(Proj.firer))
			message_admins("[key_name_admin(Proj.firer)] shot fueltank at [loc.loc.name] ([loc.x],[loc.y],[loc.z]) (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[loc.x];Y=[loc.y];Z=[loc.z]'>JMP</a>).")
			log_game("[key_name(Proj.firer)] shot fueltank at [loc.loc.name] ([loc.x],[loc.y],[loc.z]).")

		if(!istype(Proj ,/obj/item/projectile/beam/lasertag) && !istype(Proj ,/obj/item/projectile/beam/practice) )
			explode()

/// A blast sets the fuel off.
/obj/structure/reagent_dispensers/fueltank/proc/tank_blast_explode(datum/act/hit/explosion/A)
	explode()
	return TRUE

/// A blob sets the fuel off.
/obj/structure/reagent_dispensers/fueltank/dispenser_blob_burst(datum/act/hit/blob/A)
	explode()
	return TRUE

/obj/structure/reagent_dispensers/fueltank/proc/explode()
	if (reagents.total_volume > 500)
		explosion(src.loc,1,2,4)
	else if (reagents.total_volume > 100)
		explosion(src.loc,0,1,3)
	else if (reagents.total_volume > 50)
		explosion(src.loc,-1,1,2)
	if(src)
		destroyed(src, null, "explosion")

/// Heat behaviour rule: a fuel tank explodes above 500 C.
/obj/structure/reagent_dispensers/fueltank/proc/rule_explode(datum/rule/rule)
	explode()

/// Heat behaviour rule: a leaking (modded) tank explodes in any fire.
/obj/structure/reagent_dispensers/fueltank/proc/rule_modded_explode(datum/rule/rule)
	if(modded)
		explode()

/obj/structure/reagent_dispensers/fueltank/Move(atom/newloc, direct, movetime)
	if (..() && modded)
		leak_fuel(amount_per_transfer_from_this/10.0)

/obj/structure/reagent_dispensers/fueltank/proc/leak_fuel(amount)
	if (reagents.total_volume == 0)
		return
	amount = min(amount, reagents.total_volume)
	reagents.trans_to_turf(get_turf(src),amount)

/obj/structure/reagent_dispensers/peppertank
	name = "Pepper Spray Refiller"
	desc = "Refills pepper spray canisters."
	icon = 'icons/obj/objects.dmi'
	icon_state = "peppertank"
	anchored = TRUE
	density = FALSE
	amount_per_transfer_from_this = 45
	flags = WALL_ITEM

CAPABILITIES(/obj/structure/reagent_dispensers/peppertank)
	configure(reagents(starts = list(REAGENT_ID_CONDENSEDCAPSAICIN = 1000)))

/obj/structure/reagent_dispensers/virusfood
	name = "Virus Food Dispenser"
	desc = "A dispenser of virus food. Yum."
	icon = 'icons/obj/virology.dmi'
	icon_state = "virusfoodtank"
	anchored = TRUE
	density = FALSE
	amount_per_transfer_from_this = 10

CAPABILITIES(/obj/structure/reagent_dispensers/virusfood)
	configure(reagents(starts = list(REAGENT_ID_VIRUSFOOD = 1000)))

/obj/structure/reagent_dispensers/acid
	name = "Sulphuric Acid Dispenser"
	desc = "A dispenser of acid for industrial processes."
	icon = 'icons/obj/objects.dmi'
	icon_state = "acidtank"
	anchored = TRUE
	density = FALSE
	amount_per_transfer_from_this = 10

CAPABILITIES(/obj/structure/reagent_dispensers/acid)
	configure(reagents(starts = list(REAGENT_ID_SACID = 1000)))

/obj/structure/reagent_dispensers/water_cooler
	name = "Water-Cooler"
	desc = "A machine that dispenses water to drink."
	amount_per_transfer_from_this = 5
	icon = 'icons/obj/vending.dmi'
	icon_state = "water_cooler"
	possible_transfer_amounts = null
	anchored = TRUE
	has_sockets = FALSE
	var/bottle = 0
	var/cups = 0
	var/cupholder = 0
TRACKED(/obj/structure/reagent_dispensers/water_cooler, cupholder)
TRACKED(/obj/structure/reagent_dispensers/water_cooler, bottle)

/obj/structure/reagent_dispensers/water_cooler/full
	bottle = 1
	cupholder = 1
	cups = 10

CAPABILITIES(/obj/structure/reagent_dispensers/water_cooler)
	climb()
	op("interaction_hand", hand(), ungated(), then(PROC_REF(interaction_hand)))
	op("unfasten_jug", tool(TOOL_WRENCH), when(nameof(bottle)), starts(PROC_REF(jug_started)), wait(2 SECONDS), then(PROC_REF(unfasten_jug_done)))
	op("bottle", item(/obj/item/reagent_containers/glass/cooler_bottle), needs(req(PROC_REF(cooler_bolted)), req(PROC_REF(cooler_no_bottle))),
		begins(MSG(water_cooler/screwing)), wait(2 SECONDS), then(PROC_REF(bottle_done)))
	op("cupholder", stack(/obj/item/stack/material/plastic, 1), needs(req(PROC_REF(cooler_bolted)), req(PROC_REF(cooler_no_cupholder))),
		begins(MSG(water_cooler/attaching)), plays(SFX_ITEMS_DECONSTRUCT, at_start = TRUE), wait(2 SECONDS), then(PROC_REF(cupholder_done)))

/obj/structure/reagent_dispensers/water_cooler/Initialize(mapload)
	. = ..()
	if(bottle)
		reagents.add_reagent(REAGENT_ID_WATER,2000)
	make_rotatable()

/obj/structure/reagent_dispensers/water_cooler/examine(mob/user)
	. = ..()
	if(cupholder)
		. += span_notice("There are [cups] cups in the cup dispenser.")

MSG_DEF(water_cooler/screwing, "You start to screw the bottle onto the water-cooler.", "%U% starts to screw a bottle onto %T%.")
MSG_DEF(water_cooler/attaching, "You start to attach a cup dispenser onto the water-cooler.", "%U% starts to attach a cup dispenser onto %T%.")
MSG_DEF_SELF(water_cooler/unbolted, span_warning("You need to wrench down the cooler first."))
MSG_DEF_SELF(water_cooler/has_bottle, span_warning("There is already a bottle there!"))
MSG_DEF_SELF(water_cooler/has_cupholder, span_warning("There is already a cup dispenser there!"))

/// Requirement: the cooler is bolted down.
/obj/structure/reagent_dispensers/water_cooler/proc/cooler_bolted(datum/act/op/A)
	return (anchored) ? null : MSG(water_cooler/unbolted)

/// Requirement: no bottle is on it yet.
/obj/structure/reagent_dispensers/water_cooler/proc/cooler_no_bottle(datum/act/op/A)
	return (!bottle) ? null : MSG(water_cooler/has_bottle)

/// Requirement: no cup dispenser is on it yet.
/obj/structure/reagent_dispensers/water_cooler/proc/cooler_no_cupholder(datum/act/op/A)
	return (!cupholder) ? null : MSG(water_cooler/has_cupholder)

/obj/structure/reagent_dispensers/water_cooler/proc/bottle_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/cooler_bottle/G = A.held
	add_fingerprint(user)
	if(bottle || !anchored)
		return
	set_bottle(1)
	to_chat(user, span_notice("You screw the bottle onto the water-cooler!"))
	for(var/datum/reagent/R in G.reagents.reagent_list)
		var/total_reagent = G.reagents.get_reagent_amount(R.id)
		reagents.add_reagent(R.id, total_reagent)
	consume(G, user)

/obj/structure/reagent_dispensers/water_cooler/proc/cupholder_done(datum/act/op/A)
	var/mob/user = A.actor
	if(cupholder || !anchored)
		return
	add_fingerprint(user)
	to_chat(user, span_notice("You attach a cup dispenser onto the water-cooler."))
	set_cupholder(1)

/// The wrench is at the jug: the cooler takes a print and the tool its sound, as the wait starts.
/obj/structure/reagent_dispensers/water_cooler/proc/jug_started(datum/act/op/A)
	add_fingerprint(A.actor)
	playsound(src, A.held.usesound, 50, TRUE)

/obj/structure/reagent_dispensers/water_cooler/proc/unfasten_jug_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!bottle)
		return
	to_chat(user, span_notice("You unfasten the jug."))
	var/obj/item/reagent_containers/glass/cooler_bottle/jug = new(loc)
	for(var/datum/reagent/reagent in reagents.reagent_list)
		jug.reagents.add_reagent(reagent.id, reagents.get_reagent_amount(reagent.id))
	reagents.clear_reagents()
	set_bottle(FALSE)

/obj/structure/reagent_dispensers/water_cooler/wrench_act(mob/user, obj/item/tool)
	add_fingerprint(user)
	use_tool(user, tool, src, delay = 2 SECONDS, volume = 0, receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user, tool))
	return ITEM_INTERACT_SUCCESS

/obj/structure/reagent_dispensers/water_cooler/proc/wrench_act_tool_done(mob/user, obj/item/tool)
	to_chat(user, span_notice("You [anchored ? "un" : ""]secure \the [src]."))
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/structure/reagent_dispensers/water_cooler/screwdriver_act(mob/user, obj/item/tool)
	if(cupholder)
		playsound(src, tool.usesound, 50, TRUE)
		to_chat(user, span_notice("You take the cup dispenser off."))
		new /obj/item/stack/material/plastic(loc)
		for(var/i = 1 to cups)
			new /obj/item/reagent_containers/food/drinks/sillycup(loc)
		cups = 0
		set_cupholder(FALSE)
		return ITEM_INTERACT_SUCCESS
	if(bottle)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, tool, src, delay = 2 SECONDS, volume = 50, start_self = "You start taking the water-cooler apart.", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/reagent_dispensers/water_cooler/proc/screwdriver_act_tool_done(mob/user)
	if(bottle || cupholder)
		return
	to_chat(user, span_notice("You take the water-cooler apart."))
	replace_with(src, /obj/item/stack/material/plastic, 4)
	return ITEM_INTERACT_SUCCESS

/// Old attack_hand.
/obj/structure/reagent_dispensers/water_cooler/proc/interaction_hand(datum/act/op/A)
	if(cups)
		new /obj/item/reagent_containers/food/drinks/sillycup(src.loc)
		cups--
		flick("[icon_state]-vend", src)
		return TRUE
	return TRUE

/// The look (the draw sweep: from its layers).
/obj/structure/reagent_dispensers/water_cooler/draw(datum/look/look)
	..()
	switch("[bottle]")
		if("1")
			look.state("water_cooler")
			look.overlay("water_cooler_bottle")
		if("*")
			look.state("water_cooler")

/obj/structure/reagent_dispensers/beerkeg
	name = "beer keg"
	desc = "A beer keg."
	icon = 'icons/obj/objects.dmi'
	icon_state = "beertankTEMP"
	amount_per_transfer_from_this = 10


CAPABILITIES(/obj/structure/reagent_dispensers/beerkeg)
	configure(reagents(starts = list(REAGENT_ID_BEER = 1000)))
	climb()

/obj/structure/reagent_dispensers/beerkeg/wood
	name = "beer keg"
	desc = "A beer keg with a tap on it."
	icon_state = "beertankfantasy"

/obj/structure/reagent_dispensers/beerkeg/wine
	name = "wine barrel"
	desc = "A wine casket with a tap on it."
	icon_state = "beertankfantasy"

CAPABILITIES(/obj/structure/reagent_dispensers/beerkeg/wine)
	configure(reagents(starts = list(REAGENT_ID_REDWINE = 1000)))

/obj/structure/reagent_dispensers/beerkeg/fakenuke
	name = "nuclear beer keg"
	desc = "A beer keg in the form of a nuclear bomb! An absolute blast at parties!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "nuclearbomb0"

//Cooking oil refill tank
/obj/structure/reagent_dispensers/cookingoil
	name = "cooking oil tank"
	desc = "A fifty-litre tank of commercial-grade corn oil, intended for use in large scale deep fryers. Store in a cool, dark place"
	icon = 'icons/obj/objects.dmi'
	icon_state = "oiltank"
	amount_per_transfer_from_this = 120


CAPABILITIES(/obj/structure/reagent_dispensers/cookingoil)
	configure(reagents(starts = list(REAGENT_ID_COOKINGOIL = 5000)))
	climb()
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(tank_blast_explode))))

/obj/structure/reagent_dispensers/cookingoil/bullet_act(obj/item/projectile/Proj)
	if(Proj.get_structure_damage())
		explode()

/// A blast bursts the barrel.
/obj/structure/reagent_dispensers/cookingoil/proc/tank_blast_explode(datum/act/hit/explosion/A)
	explode()
	return TRUE

/obj/structure/reagent_dispensers/cookingoil/proc/explode()
	reagents.splash_area(get_turf(src), 3)
	visible_message(span_danger("The [src] bursts open, spreading oil all over the area."))
	destroyed(src, null, BRUTE)

/obj/structure/reagent_dispensers/bloodbarrel
	name = "blood barrel"
	desc = "A beer keg."
	icon = 'icons/obj/chemical_tanks.dmi'
	icon_state = "bloodbarrel"
	amount_per_transfer_from_this = 10

CAPABILITIES(/obj/structure/reagent_dispensers/bloodbarrel)
	climb()

/obj/structure/reagent_dispensers/bloodbarrel/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_BLOOD, 1000, list("donor"=null,"viruses"=null,"blood_DNA"=null,"blood_type"="O-","resistances"=null,"trace_chem"=null,"changeling"=FALSE))


/obj/structure/reagent_dispensers/space_cleaner
	name = "Space Cleaner Dispenser"
	desc = "A dispenser of space cleaner, every janitor's dream!"
	icon = 'icons/obj/objects.dmi'
	icon_state = "virusfoodtank"
	amount_per_transfer_from_this = 60
	anchored = 1

CAPABILITIES(/obj/structure/reagent_dispensers/space_cleaner)
	configure(reagents(starts = list(REAGENT_ID_CLEANER = 1000)))

