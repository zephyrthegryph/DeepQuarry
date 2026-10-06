// Use this define to register something as a creatable!
// * n - The proper name of the purchasable
// * o - The object type path of the purchasable to spawn
// * r - The maximum amount to dispense
// * p - The price of the purchasable in biomass
#define BIOGEN_ITEM(n, o, r, p) n = new /datum/data/biogenerator_item(n, o, r, p)

// Use this define to register something as dispensable
// * n - The proper name of the purchasable
// * o - The reagent ID
// * r - The maximum amount to dispense
// * p - The price of the purchasable in biomass
#define BIOGEN_REAGENT(n, o, r, p) n = new /datum/data/biogenerator_reagent(n, o, r, p)

/obj/machinery/biogenerator
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 40
	name = "biogenerator"
	desc = "Converts plants into biomass, which can be used for fertilizer and sort-of-synthetic products."
	icon = 'icons/obj/biogenerator_vr.dmi'
	icon_state = "biogen-stand"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/biogenerator
	use_power = USE_POWER_IDLE
	idle_power_usage = 40
	var/processing = 0
	var/obj/item/reagent_containers/glass/beaker = null
	var/points = 0
	var/build_eff = 1
	var/eat_eff = 1

	var/list/item_list


/datum/data/biogenerator_item
	var/equipment_path = null
	var/equipment_amt = 1
	var/cost = 0

/datum/data/biogenerator_item/New(name, path, amt, cost)
	src.name = name
	src.equipment_path = path
	src.equipment_amt = amt
	src.cost = cost

/datum/data/biogenerator_reagent
	var/reagent_id = null
	var/reagent_amt = 0
	var/cost = 0

/datum/data/biogenerator_reagent/New(name, id, amt, cost)
	src.name = name
	src.reagent_id = id
	src.reagent_amt = amt
	src.cost = cost

/obj/machinery/biogenerator/Initialize(mapload)
	. = ..()
	var/datum/reagents/R = new/datum/reagents(1000)
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)

	default_apply_parts()

	item_list = list()
	item_list["Food Items"] = list(
		BIOGEN_REAGENT("Milk", REAGENT_ID_MILK, 50, 2), //2 for each 1u
		BIOGEN_REAGENT("Cream", REAGENT_ID_CREAM, 50, 3), //3 for each 1u
		BIOGEN_ITEM("Slab of meat", /obj/item/reagent_containers/food/snacks/meat, 5, 50),
		BIOGEN_ITEM("Algae Sheets", /obj/item/stack/material/algae, 50, 100),
	)
	item_list["Cooking Ingredients"] = list(
		BIOGEN_REAGENT("Universal Enzyme", REAGENT_ID_ENZYME, 50, 3),
		BIOGEN_ITEM("Nutri-spread", /obj/item/reagent_containers/food/snacks/spreads, 5, 30),
		BIOGEN_REAGENT("Salt", REAGENT_ID_SODIUMCHLORIDE, 50, 2),
		BIOGEN_REAGENT("Soy Sauce", REAGENT_ID_SOYSAUCE, 50, 3),
	)
	item_list["Gardening Nutrients"] = list(
		BIOGEN_ITEM("E-Z-Nutrient", /obj/item/reagent_containers/glass/bottle/eznutrient, 5, 30),
		BIOGEN_ITEM("Left 4 Zed", /obj/item/reagent_containers/glass/bottle/left4zed, 5, 50),
		BIOGEN_ITEM("Robust Harvest", /obj/item/reagent_containers/glass/bottle/robustharvest, 5, 50),
		BIOGEN_ITEM("Diethylamine", /obj/item/reagent_containers/glass/bottle/diethylamine, 5, 60),
		BIOGEN_ITEM("Mutagen", /obj/item/reagent_containers/glass/bottle/mutagen, 15, 50),
		BIOGEN_ITEM("Plant-B-Gone", /obj/item/reagent_containers/spray/plantbgone, 5, 50),
	)
	item_list["Exotic Seeds"] = list(
		BIOGEN_ITEM("Mystery seed pack", /obj/item/seeds/random, 5, 150),
		BIOGEN_ITEM("Kudzu seed pack", /obj/item/seeds/kudzuseed, 5, 100),
	)
	item_list["Leather Products"] = list(
		BIOGEN_ITEM("Wallet", /obj/item/storage/wallet, 1, 100),
		BIOGEN_ITEM("Botanical gloves", /obj/item/clothing/gloves/botanic_leather, 1, 250),
		BIOGEN_ITEM("Plant bag", /obj/item/storage/bag/plants, 1, 320),
		BIOGEN_ITEM("Large plant bag", /obj/item/storage/bag/plants/large, 1, 640),
		BIOGEN_ITEM("Utility belt", /obj/item/storage/belt/utility, 1, 300),
		BIOGEN_ITEM("Leather Satchel", /obj/item/storage/backpack/satchel, 1, 400),
		BIOGEN_ITEM("Cash Bag", /obj/item/storage/bag/cash, 1, 400),
		BIOGEN_ITEM("Chemistry Bag", /obj/item/storage/bag/chemistry, 1, 400),
		BIOGEN_ITEM("Workboots", /obj/item/clothing/shoes/boots/workboots, 1, 400),
		BIOGEN_ITEM("Leather Chaps", /obj/item/clothing/under/pants/chaps, 1, 400),
		BIOGEN_ITEM("Leather Coat", /obj/item/clothing/suit/leathercoat, 1, 500),
		BIOGEN_ITEM("Leather Jacket", /obj/item/clothing/suit/storage/toggle/brown_jacket, 1, 500),
		BIOGEN_ITEM("Winter Coat", /obj/item/clothing/suit/storage/hooded/wintercoat, 1, 500),
	)

/obj/machinery/biogenerator/tgui_static_data(mob/user)
	var/list/static_data = list()

	// Available items - in static data because we don't wanna compute this list every time! It hardly changes.
	static_data["items"] = list()
	for(var/cat in item_list)
		var/list/cat_items = list()
		for(var/prize_name, value in item_list[cat])
			if(istype(value, /datum/data/biogenerator_item))
				var/datum/data/biogenerator_item/cat_item = value
				cat_items[prize_name] = list("name" = prize_name, "price" = cat_item.cost, "max_amount" = cat_item.equipment_amt)
				continue
			var/datum/data/biogenerator_reagent/cat_reag = value
			cat_items[prize_name] = list("name" = prize_name, "price" = cat_reag.cost, "max_amount" = cat_reag.reagent_amt, "reagent" = TRUE)

		static_data["items"][cat] = cat_items

	return static_data

/obj/machinery/biogenerator/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["beaker"] = !!beaker

	data["build_eff"] = build_eff
	data["points"] = points
	data["processing"] = processing
	return data

CAPABILITIES(/obj/machinery/biogenerator)
	interface("Biogenerator")
	op("activate", ui_act("activate"), then(PROC_REF(ui_act_activate)))
	op("detach", ui_act("detach"), then(PROC_REF(ui_act_detach)))
	op("purchase", ui_act("purchase", arg("amount", num()), arg("cat", schema_text(4096)), arg("name", schema_text(4096))), then(PROC_REF(ui_act_purchase)))

/obj/machinery/biogenerator/proc/ui_act_activate(datum/act/op/A)
	var/mob/user = A.actor
	activate(user)
	return TRUE

/obj/machinery/biogenerator/proc/ui_act_detach(datum/act/op/A)
	if(beaker)
		beaker.forceMove(loc)
		own_take(src, nameof(/obj/machinery/biogenerator::beaker))
	return TRUE

/obj/machinery/biogenerator/proc/ui_act_purchase(datum/act/op/A, raw_amount, cat, raw_name)
	var/mob/user = A.actor
	var/category = cat // meow
	var/name = raw_name
	var/amount = raw_amount

	if(!(category in item_list) || !(name in item_list[category]) || !isnum(amount)) // Not trying something that's not in the list, are you?
		return FALSE

	var/datum/data/biogenerator_item/bi = item_list[category][name]

	if(!istype(bi))
		var/datum/data/biogenerator_reagent/br = item_list[category][name]
		if(!istype(br))
			return FALSE
		if(!beaker)
			return FALSE
		if(amount <= 0 || amount > br.reagent_amt)
			return FALSE
		var/cost = round(br.cost / build_eff)
		if(cost < 1) //No going below 1 cost.
			cost = 1
		if(cost * amount > points)
			to_chat(user, span_danger("Insufficient biomass."))
			return FALSE
		var/amt_to_actually_dispense = round(min(beaker.reagents.get_free_space(), amount))
		if(amt_to_actually_dispense <= 0)
			to_chat(user, span_danger("The loaded beaker is full!"))
			return FALSE
		points -= cost * amt_to_actually_dispense
		beaker.reagents.add_reagent(br.reagent_id, amt_to_actually_dispense)
		play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
		return FALSE

	if(amount <= 0 || amount > bi.equipment_amt)
		return FALSE

	var/cost = round(bi.cost / build_eff)
	if(cost > points)
		to_chat(user, span_danger("Insufficient biomass."))
		return FALSE

	points -= cost * amount
	if(ispath(bi.equipment_path, /obj/item/stack))
		new bi.equipment_path(loc, amount)
		play_sfx(src, SFX_MACHINES_VENDING_VENDING_DROP)
		return TRUE

	for(var/i in 1 to amount)
		new bi.equipment_path(loc)
		play_sfx(src, SFX_MACHINES_VENDING_VENDING_DROP)
	return TRUE

/obj/machinery/biogenerator/on_reagent_change()			//When the reagents change, change the icon as well.
	changed(src)

/obj/machinery/biogenerator/proc/appearance_state()
	if(!beaker)
		return "empty"
	return processing ? "work" : "stand"

/// The look (the draw sweep: from its template).
/obj/machinery/biogenerator/draw(datum/look/look)
	..()
	look.state("biogen-[appearance_state()]")

/obj/machinery/biogenerator/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/biogenerator_insert,
		/datum/interaction/machine_hand/ungated/biogenerator_use,
	)
	..()

/// The old attackby: insert a beaker, bulk-insert a plant bag, or insert one grown item.
/datum/interaction/machine_item/biogenerator_insert
	id = "biogenerator_insert"
	name = "Insert"
	held_type = /obj/item
	effect = /obj/machinery/biogenerator/proc/interaction_insert

/obj/machinery/biogenerator/proc/interaction_insert(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/reagent_containers/glass))
		if(beaker)
			to_chat(user, span_notice("\The [src] is already loaded."))
		else
			move_into(src, nameof(src.beaker), O, user)
	else if(processing)
		to_chat(user, span_notice("\The [src] is currently processing."))
	else if(istype(O, /obj/item/storage/bag/plants))
		var/i = 0
		latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/item/reagent_containers/food/snacks/grown/G in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			i++
		if(i >= 10)
			to_chat(user, span_notice("\The [src] is already full! Activate it."))
		else
			for(var/obj/item/reagent_containers/food/snacks/grown/G in contents_of(O))
				if(!own_bring_in(src, nameof(contents), G, null, user, TRUE, null, FALSE))
					continue
				i++
				if(i >= 10)
					to_chat(user, span_notice("You fill \the [src] to its capacity."))
					break
			if(i < 10)
				to_chat(user, span_notice("You empty \the [O] into \the [src]."))


	else if(!istype(O, /obj/item/reagent_containers/food/snacks/grown))
		to_chat(user, span_notice("You cannot put this in \the [src]."))
	else
		var/i = 0
		latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/item/reagent_containers/food/snacks/grown/G in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			i++
		if(i >= 10)
			to_chat(user, span_notice("\The [src] is full! Activate it."))
		else
			if(!own_bring_in(src, nameof(contents), O, null, user, TRUE, null, FALSE))
				return TRUE
			to_chat(user, span_notice("You put \the [O] in \the [src]"))
	changed(src)
	return TRUE

/// The old attack_hand: never called ..(), just checked BROKEN then opened the UI.
/datum/interaction/machine_hand/ungated/biogenerator_use
	id = "biogenerator_use"
	name = "Use"
	effect = /obj/machinery/biogenerator/proc/interaction_use

/obj/machinery/biogenerator/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_stat(BROKEN))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/biogenerator/proc/activate(mob/user)
	if(user.stat)
		return
	if(has_stat(MACHINE_STAT_ANY)) //NOPOWER etc
		return
	if(processing)
		to_chat(user, span_notice("The biogenerator is in the process of working."))
		return
	var/S = 0
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/reagent_containers/food/snacks/grown/I in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		S += 5
		if(I.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) < 0.1)
			points += 1
		else points += I.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) * 10 * eat_eff
		consume(I)
	if(!S)
		to_chat(user, span_warning("Error: No growns inside. Please insert growns."))
		return

	processing = 1
	changed(src)
	play_sfx(src, SFX_MACHINES_BLENDER, 0.8)
	use_power(S * 30)
	after(src, (S * (0.1 SECONDS) + 1.5 SECONDS) / eat_eff, PROC_REF(finish_processing))

/obj/machinery/biogenerator/proc/finish_processing()
	processing = 0
	SStgui.update_uis(src)
	play_sfx(src, SFX_MACHINES_BIOGENERATOR_END)
	changed(src)

/obj/machinery/biogenerator/RefreshParts()
	..()
	var/man_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	var/bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)

	build_eff = man_rating
	eat_eff = bin_rating

#undef BIOGEN_ITEM
#undef BIOGEN_REAGENT

/obj/machinery/biogenerator/ownership()
	. = ..()
	. += owns(nameof(beaker), policy = OWN_CONTAINED, starts = /obj/item/reagent_containers/glass/bottle)
