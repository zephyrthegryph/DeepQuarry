#define ICECREAM_VANILLA 1
#define ICECREAM_CHOCOLATE 2
#define ICECREAM_STRAWBERRY 3
#define ICECREAM_BLUE 4
#define CONE_WAFFLE 5
#define CONE_CHOC 6

// Ported wholesale from Apollo Station.

/obj/machinery/icecream_vat
	name = "icecream vat"
	desc = "Ding-aling ding dong. Get your NanoTrasen-approved ice cream!"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "icecream_vat"
	density = TRUE
	anchored = FALSE
	maintenance_flags = MACHINE_MAINT_STANDARD
	use_power = USE_POWER_OFF
	flags = OPENCONTAINER | NOREACT

	var/list/product_types
	var/dispense_flavour = ICECREAM_VANILLA
	var/flavour_name = "vanilla"

/// Reagents each flavour / cone uses, indexed by ICECREAM_* / CONE_*. Shared, read-only.
GLOBAL_LIST_INIT(icecream_ingredients, list( 	list(REAGENT_ID_MILK, REAGENT_ID_ICE), 	list(REAGENT_ID_MILK, REAGENT_ID_ICE, REAGENT_ID_COCO), 	list(REAGENT_ID_MILK, REAGENT_ID_ICE, REAGENT_ID_BERRYJUICE), 	list(REAGENT_ID_MILK, REAGENT_ID_ICE, REAGENT_ID_SINGULO), 	list(REAGENT_ID_FLOUR, REAGENT_ID_SUGAR), 	list(REAGENT_ID_FLOUR, REAGENT_ID_SUGAR, REAGENT_ID_COCO), ))

/obj/machinery/icecream_vat/proc/get_ingredient_list(type)
	if(!isnum(type) || type < ICECREAM_VANILLA || type > CONE_CHOC)
		type = ICECREAM_VANILLA
	return GLOB.icecream_ingredients[type]

/obj/machinery/icecream_vat/proc/get_flavour_name(flavour_type)
	switch(flavour_type)
		if(ICECREAM_CHOCOLATE)
			return "chocolate"
		if(ICECREAM_STRAWBERRY)
			return "strawberry"
		if(ICECREAM_BLUE)
			return "blue"
		if(CONE_WAFFLE)
			return "waffle"
		if(CONE_CHOC)
			return "chocolate"
		else
			return "vanilla"

/obj/machinery/icecream_vat/Initialize(mapload)
	. = ..()
	while(length(product_types) < 6)
		LAZYADD(product_types, 5)

CAPABILITIES(/obj/machinery/icecream_vat)
	reagents(100, starts = list(REAGENT_ID_MILK = 5, REAGENT_ID_FLOUR = 5, REAGENT_ID_SUGAR = 5, REAGENT_ID_ICE = 5))
	interface("IcecreamVat")
	without("ui_open")
	op("index_action", ui_act("index_action", arg("iceIndex", num())), then(PROC_REF(ui_act_index_action)))
	op("make_type", ui_act("make_type", arg("amount", num()), arg("index", num())), then(PROC_REF(ui_act_make_type)))
	op("clear_reagent", ui_act("clear_reagent", arg("id", schema_text(4096))), then(PROC_REF(ui_act_clear_reagent)))
	op("icecream_vat_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(icecream_vat_interaction_item)))

/obj/machinery/icecream_vat/proc/build_icecream_data(list/ice_types)
	var/ice_data = list()
	if(!length(ice_types))
		return ice_data
	for(var/entry in ice_types)
		UNTYPED_LIST_ADD(ice_data, list("index" = entry, "name" = get_flavour_name(entry), "amount_left" = LAZYACCESS(product_types, entry), "ingredients" = get_ingredient_list(entry)))
	return ice_data

/// /obj/machinery/icecream_vat's window data.
/obj/machinery/icecream_vat/ui_data(datum/act/eval/A)
	var/list/reagent_data = list()
	for(var/datum/reagent/current_reagent in reagents.reagent_list)
		UNTYPED_LIST_ADD(reagent_data, list("name" = current_reagent.name, "volume" = current_reagent.volume, "id" = current_reagent.id))

	return list(
		"current_flavor" = flavour_name,
		"icecrem_data" = build_icecream_data(list(ICECREAM_VANILLA, ICECREAM_STRAWBERRY, ICECREAM_CHOCOLATE, ICECREAM_BLUE)),
		"cone_data" = build_icecream_data(list(CONE_WAFFLE, CONE_CHOC)),
		"reagent_data" = reagent_data
	)

/obj/machinery/icecream_vat/proc/ui_act_index_action(datum/act/op/A, iceIndex)
	var/mob/user = A.actor
	var/index_action = iceIndex
	if(index_action <= 0)
		return FALSE
	if(index_action < 5)
		dispense_flavour = index_action
		flavour_name = get_flavour_name(dispense_flavour)
		act_message(user, src, MSG_SELF(span_notice("You set %T% to dispense [flavour_name] flavoured icecream.")), MSG_OTHERS(span_notice("%U% sets %T% to dispense [flavour_name] flavoured icecream.")))
		return TRUE
	if(index_action < 7)
		var/cone_name = get_flavour_name(index_action)
		if(LAZYACCESS(product_types, index_action) >= 1)
			product_types[index_action] -= 1
			var/obj/item/reagent_containers/food/snacks/icecream/I = new(src.loc)
			I.cone_type = cone_name
			I.icon_state = "icecream_cone_[cone_name]"
			I.desc = "Delicious [cone_name] cone, but no ice cream."
			act_message(user, src, MSG_SELF(span_info("You dispense a crunchy [cone_name] cone from %T%.")), MSG_OTHERS(span_info("%U% dispenses a crunchy [cone_name] cone from %T%.")))
		else
			to_chat(user, span_warning("There are no [cone_name] cones left!"))
	return TRUE

/obj/machinery/icecream_vat/proc/ui_act_make_type(datum/act/op/A, amount_arg, index_arg)
	var/mob/user = A.actor
	var/amount = amount_arg
	if(amount <= 0 || amount > 10)
		return FALSE
	var/index = index_arg
	if(index <= 0 || index > 6)
		return FALSE
	make(user, index, amount)
	return TRUE

/obj/machinery/icecream_vat/proc/ui_act_clear_reagent(datum/act/op/A, id)
	var/reagent_id = id
	if(!reagent_id)
		return FALSE
	reagents.del_reagent(reagent_id)
	return TRUE

/// Old attackby.
/obj/machinery/icecream_vat/proc/icecream_vat_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(default_part_replacement(user, O))
		return OP_PASS
	if(istype(O, /obj/item/reagent_containers/food/snacks/icecream))
		var/obj/item/reagent_containers/food/snacks/icecream/I = O
		if(!I.ice_creamed)
			if(LAZYACCESS(product_types, dispense_flavour) > 0)
				act_message(user, src, others = "[icon2html(src,viewers(src))] " + span_info("%U% scoops delicious [flavour_name] icecream into [I]."))
				product_types[dispense_flavour] -= 1
				I.add_ice_cream(flavour_name)
				if(I.reagents.total_volume < 10)
					I.reagents.add_reagent(REAGENT_ID_SUGAR, 10 - I.reagents.total_volume)
			else
				to_chat(user, span_warning("There is not enough icecream left!"))
		else
			to_chat(user, span_notice("[O] already has icecream in it."))
		return OP_OK
	else if(O.is_open_container())
		return OP_PASS
	return OP_DECLINE

/obj/machinery/icecream_vat/proc/make(mob/user, make_type, amount)
	for(var/R in get_ingredient_list(make_type))
		if(reagents.has_reagent(R, amount))
			continue
		amount = 0
		break
	if(amount)
		for(var/R in get_ingredient_list(make_type))
			reagents.remove_reagent(R, amount)
		LAZYADDASSOC(product_types, make_type, amount)
		var/flavour = get_flavour_name(make_type)
		if(make_type > 4)
			act_message(user, src, others = span_info("%U% cooks up some [flavour] cones."))
		else
			act_message(user, src, others = span_info("%U% whips up some [flavour] icecream."))
	else
		to_chat(user, span_warning("You don't have the ingredients to make this."))

/obj/item/reagent_containers/food/snacks/icecream
	name = "ice cream cone"
	desc = "Delicious waffle cone, but no ice cream."
	icon_state = "icecream_cone_waffle" //default for admin-spawned cones, href_list["cone"] should overwrite this all the time
	bitesize = 3

	var/ice_creamed = 0
	var/cone_type

CAPABILITIES(/obj/item/reagent_containers/food/snacks/icecream)
	configure(reagents(volume = 20, add = list(REAGENT_ID_NUTRIMENT = 5)))

/obj/item/reagent_containers/food/snacks/icecream/proc/add_ice_cream(flavour_name)
	name = "[flavour_name] icecream"
	add_overlay("icecream_[flavour_name]")
	desc = "Delicious [cone_type] cone with a dollop of [flavour_name] ice cream."
	ice_creamed = 1

#undef ICECREAM_VANILLA
#undef ICECREAM_CHOCOLATE
#undef ICECREAM_STRAWBERRY
#undef ICECREAM_BLUE
#undef CONE_WAFFLE
#undef CONE_CHOC
