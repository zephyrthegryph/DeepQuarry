/obj/machinery/food_replicator
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	name = "Food Replicator"
	icon = 'icons/obj/machines/food_replicator.dmi'
	icon_state = "food_replicator"

	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 200

	var/print_delay = 150
	var/print_cost

	var/efficiency = 1.35
	var/speed = 1

	var/obj/item/reagent_containers/container = null
	var/printing = FALSE
	var/list/products = list()

/obj/item/circuitboard/food_replicator
	name = T_BOARD("food replicator")
	build_path = /obj/machinery/food_replicator
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stock_parts/capacitor = 3,
		/obj/item/stock_parts/matter_bin = 2,
		/obj/item/stock_parts/manipulator = 1,
		/obj/item/stock_parts/motor = 1,
		/obj/item/stack/cable_coil = 5,
	)

/obj/machinery/food_replicator/Initialize(mapload)
	. = ..()

	default_apply_parts()

/obj/machinery/food_replicator/dismantle()
	var/turf/T = get_turf(src)
	if(T)
		if(container)
			container.forceMove(T)
			container = null
	QDEL_NULL_LIST(products)
	return ..()

/obj/machinery/food_replicator/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/food_replicator_scan,
		/datum/interaction/machine_item/food_replicator_insert_container,
		/datum/interaction/machine_hand/ungated/food_replicator_use,
		/datum/interaction/machine_verb/food_replicator_eject_beaker,
	)
	..()

/// Old attack_hand (never called ..()): opens the print dialogue.
/datum/interaction/machine_hand/ungated/food_replicator_use
	id = "food_replicator_use"
	name = "Use"
	effect = /obj/machinery/food_replicator/proc/interaction_use

/obj/machinery/food_replicator/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(stat & (BROKEN|NOPOWER))
		return TRUE

	if(panel_open)
		to_chat(user, span_warning("Close the panel first!"))
		return TRUE

	if(printing)
		to_chat(user, span_warning("\The [src] is busy!"))
		return TRUE

	interact(user)
	return TRUE

/obj/machinery/food_replicator/interact(mob/user)
	if(!isemptylist(products))
		var/choice = tgui_input_list(user, "What would you like to print?", "Print a dish", products)

		if(!choice || printing || (stat & (BROKEN|NOPOWER)))
			return

		var/product_path = products[choice]
		var/obj/item/reagent_containers/foodItem = new product_path

		var/total = foodItem.reagents.total_volume
		qdel(foodItem)

		if(!container)
			to_chat(user, span_warning("There is no container!"))
			return

		if(container && container.reagents)
			if(!container.reagents.has_reagent(REAGENT_ID_NUTRIMENT, (total*efficiency)))
				playsound(src, "sound/machines/buzz-sigh.ogg", 25, 0)
				to_chat(user, span_warning("Not enough nutriment available!"))
				return

			container.reagents.remove_reagent(REAGENT_ID_NUTRIMENT, (total*efficiency))

			update_use_power(USE_POWER_ACTIVE)
			printing = TRUE
			update_icon()

			if(product_path)
				foodItem = new product_path(src)

				if(istype(foodItem, /obj/item/reagent_containers/food/snacks/donkpocket))
					var/obj/item/reagent_containers/food/snacks/donkpocket/donkp = foodItem
					donkp.heat()

				if(foodItem.reagents.has_reagent("supermatter"))
					self_destruct()

			visible_message(span_notice("\The [src] begins to shape a nutriment slurry."))

			sleep(print_delay/speed)

			ping()
			update_use_power(USE_POWER_IDLE)
			printing = FALSE
			update_icon()

			if(!src || (stat & (BROKEN|NOPOWER)))
				return

			if(foodItem)
				foodItem.forceMove(get_turf(src))

	else
		to_chat(user, span_warning("There is no food to replicate!"))


/// Scan a food item to learn its recipe.
/datum/interaction/machine_item/food_replicator_scan
	id = "food_replicator_scan"
	name = "Scan food"
	held_type = /obj/item/reagent_containers/food
	effect = /obj/machinery/food_replicator/proc/interaction_scan

/obj/machinery/food_replicator/proc/interaction_scan(mob/user, obj/item/reagent_containers/food/O, datum/interaction/interaction)
	balloon_alert(user, "scanning...")
	if(!do_after(user, 10, src))
		return TRUE
	foodcheck(O)
	return TRUE

/// Insert a reagent container to supply nutriment.
/datum/interaction/machine_item/food_replicator_insert_container
	id = "food_replicator_insert_container"
	name = "Insert container"
	held_type = /obj/item/reagent_containers/glass
	effect = /obj/machinery/food_replicator/proc/interaction_insert_container

/obj/machinery/food_replicator/proc/interaction_insert_container(mob/user, obj/item/reagent_containers/glass/O, datum/interaction/interaction)
	if(!isnull(container))
		to_chat(user, span_warning("There is already a reagent container inserted!"))
		return TRUE

	user.drop_item()
	O.loc = src
	container = O
	balloon_alert(user, "placed \the [O] in \the [src]")
	return TRUE

/obj/machinery/food_replicator/proc/foodcheck(obj/item/reagent_containers/food)
	var/mob/living/mob = locate(/mob/living) in food
	if(mob)
		playsound(src, "sound/machines/buzz-two.ogg", 25, 0)
		return

	var/food_name = food.name
	var/path = food.type

	if(!products[food_name])
		products[food_name] = path
		playsound(src, "sound/machines/ping.ogg", 25, 0)
	else
		playsound(src, "sound/machines/buzz-sigh.ogg", 25, 0)

	return

/obj/machinery/food_replicator/update_icon()
	cut_overlays()

	icon_state = initial(icon_state)

	if(stat & BROKEN)
		icon_state = "destroyed"
	if(panel_open)
		add_overlay("panel_open")
	if(stat & (NOPOWER|EMPED))
		add_overlay("poweroff")
	if(printing)
		add_overlay("printing")

/obj/machinery/food_replicator/process()
	if(stat & (NOPOWER|BROKEN|EMPED))
		update_use_power(USE_POWER_OFF)
		return
	if(printing)
		update_use_power(USE_POWER_ACTIVE)
		return
	else
		use_power = USE_POWER_IDLE

/obj/machinery/food_replicator/RefreshParts()
	var/cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	var/man_rating = get_part_rating(/obj/item/stock_parts/manipulator)

	// A replicator built without a board has no parts: rate it as stock (rating 1).
	efficiency = 3 / max(man_rating, 1)
	speed = max(cap_rating, 1) / 2


/// Old verb/eject_beaker().
/datum/interaction/machine_verb/food_replicator_eject_beaker
	id = "food_replicator_eject_beaker"
	name = "Eject Beaker"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/food_replicator/proc/interaction_eject_beaker

/obj/machinery/food_replicator/proc/interaction_eject_beaker(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	remove_beaker()
	return TRUE

/obj/machinery/food_replicator/proc/remove_beaker()
	if(container)
		container.forceMove(get_turf(src))
		container = null
		return TRUE
	return FALSE

/obj/machinery/food_replicator/proc/self_destruct()
	visible_message(span_warning("Whirrs and spouts, starting to heat up!"))
	playsound(src, pick('sound/effects/Glassbr1.ogg', 'sound/effects/Glassbr2.ogg', 'sound/effects/Glassbr3.ogg'), 50, 1)

	message_admins("[src] attempted to create an EX donk pocket at [x], [y], [z], last touched by [forensic_data?.get_lastprint()]")
	log_game("[src] attempted to create an EX donk pocket at [x], [y], [z], last touched by [forensic_data?.get_lastprint()]. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)", 1)

	sleep(6 SECONDS) // GET OUT, GET OUT
	stat = BROKEN
	update_icon()
	explosion(src, 0, 0, 2)
	return
