/obj/machinery/food_replicator
	step_on_power_change = TRUE
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
	var/list/products = list() // ALLOW(instance_list): d: the replicator menu, filled at init

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

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/food_replicator/Initialize(mapload)
	. = ..()

	default_apply_parts()

/obj/machinery/food_replicator/dismantle()
	var/turf/T = get_turf(src)
	if(T)
		if(container)
			container.forceMove(T)
			own_take(src, nameof(container))
	QDEL_NULL_LIST(products)
	return ..()

/obj/machinery/food_replicator/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!operable())
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
		open_request(src, /datum/prompt/choice, PROC_REF(dish_chosen), answerer = user, question = "What would you like to print?", title = "Print a dish", choices = products, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	else
		to_chat(user, span_warning("There is no food to replicate!"))

/obj/machinery/food_replicator/proc/dish_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/choice = A.answer.value
	if(printing || (!operable()))
		return

	var/product_path = products[choice]
	var/obj/item/reagent_containers/foodItem = new product_path

	var/total = foodItem.reagents.total_volume
	spent(foodItem)

	if(!container)
		to_chat(user, span_warning("There is no container!"))
		return

	if(container && container.reagents)
		if(!container.reagents.has_reagent(REAGENT_ID_NUTRIMENT, (total*efficiency)))
			playsound(src, "sound/machines/buzz-sigh.ogg", 25, 0)
			to_chat(user, span_warning("Not enough nutriment available!"))
			return

		container.reagents.remove_reagent(REAGENT_ID_NUTRIMENT, (total*efficiency))

		set_use_power(USE_POWER_ACTIVE)
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

		after(src, print_delay/speed, PROC_REF(print_done), with = list(foodItem))


/obj/machinery/food_replicator/proc/interaction_scan(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/O = A.held
	balloon_alert(user, "scanning...")
	task_timed(user, 10, target = src, receiver = src, on_done = PROC_REF(interaction_scan_timed_done), done_args = list(O))
	return TRUE

/obj/machinery/food_replicator/proc/interaction_scan_timed_done(obj/item/reagent_containers/food/O)
	foodcheck(O)
	return TRUE

MSG_DEF_SELF(food_replicator/container, "There is already a reagent container inserted.")

/obj/machinery/food_replicator/proc/interaction_insert_container(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/O = A.held
	if(!move_into(src, nameof(src.container), O, user))
		return TRUE
	balloon_alert(user, "placed \the [O] in \the [src]")
	return TRUE

/obj/machinery/food_replicator/proc/foodcheck(obj/item/reagent_containers/food)
	var/mob/living/mob = locate_within(food, /mob/living)
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

/obj/machinery/food_replicator/proc/appearance_broken()
	return has_stat(BROKEN) ? 1 : 0

/obj/machinery/food_replicator/proc/appearance_nopower()
	return has_stat(NOPOWER | EMPED) ? 1 : 0

APPEARANCE_TEMPLATE(/obj/machinery/food_replicator, "{initial(icon_state)}")
DECLARE_APPEARANCE(/obj/machinery/food_replicator, "appearance_broken", list("1" = list(APPEARANCE_ICON_STATE = "destroyed")))
DECLARE_APPEARANCE(/obj/machinery/food_replicator, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("panel_open"))))
DECLARE_APPEARANCE(/obj/machinery/food_replicator, "appearance_nopower", list("1" = list(APPEARANCE_OVERLAYS = list("poweroff"))))
DECLARE_APPEARANCE(/obj/machinery/food_replicator, "printing", list("1" = list(APPEARANCE_OVERLAYS = list("printing"))))

/// Reconciles its power draw with its state on every power or break change; printing sets its
/// own draw while it runs.
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/food_replicator)
	started_work(step = PROC_REF(work_step), wakes_on = list(nameof(stat)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	op("scan", item(/obj/item/reagent_containers/food), priority(OP_PRIORITY_DEFAULT - 1), label("Scan food"), then(PROC_REF(interaction_scan)))
	op("insert_container", item(/obj/item/reagent_containers/glass), priority(OP_PRIORITY_DEFAULT - 1), label("Insert container"), needs(req_is(nameof(container), FALSE, because = MSG(food_replicator/container))), then(PROC_REF(interaction_insert_container)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("eject_beaker", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject Beaker"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds), because = PROC_REF(dq_actor_can_act_refusal))), then(PROC_REF(interaction_eject_beaker)))

/obj/machinery/food_replicator/proc/work_step(datum/act/timer/A)
	if(!operable())
		set_use_power(USE_POWER_OFF)
		return PROCESS_KILL
	if(printing)
		set_use_power(USE_POWER_ACTIVE)
		return PROCESS_KILL
	set_use_power(USE_POWER_IDLE)
	return PROCESS_KILL

/obj/machinery/food_replicator/RefreshParts()
	var/cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	var/man_rating = get_part_rating(/obj/item/stock_parts/manipulator)

	// A replicator built without a board has no parts: rate it as stock (rating 1).
	efficiency = 3 / max(man_rating, 1)
	speed = max(cap_rating, 1) / 2


/// Requirement (was REQ_* dq_actor_can_act): the legacy check answers TRUE to pass.
/obj/machinery/food_replicator/proc/dq_actor_can_act_holds(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why dq_actor_can_act_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/food_replicator/proc/dq_actor_can_act_refusal(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return istext(answer) ? answer : "you can't do that right now"

/obj/machinery/food_replicator/proc/interaction_eject_beaker(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	remove_beaker()
	return TRUE

/obj/machinery/food_replicator/proc/print_done(obj/item/reagent_containers/foodItem)
	ping()
	set_use_power(USE_POWER_IDLE)
	printing = FALSE
	update_icon()

	if(!operable())
		return

	if(foodItem)
		foodItem.forceMove(get_turf(src))

/obj/machinery/food_replicator/proc/remove_beaker()
	if(container)
		container.forceMove(get_turf(src))
		own_take(src, nameof(container))
		return TRUE
	return FALSE

/obj/machinery/food_replicator/proc/self_destruct()
	visible_message(span_warning("Whirrs and spouts, starting to heat up!"))
	play_sfx(src, SFX_SHATTER, volume = 50)

	message_admins("[src] attempted to create an EX donk pocket at [x], [y], [z], last touched by [forensic_data?.get_lastprint()]")
	log_game("[src] attempted to create an EX donk pocket at [x], [y], [z], last touched by [forensic_data?.get_lastprint()]. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)", 1)

	after(src, 6 SECONDS, PROC_REF(self_destruct_boom)) // GET OUT, GET OUT

/obj/machinery/food_replicator/proc/self_destruct_boom()
	atom_break()
	explosion(src, 0, 0, 2)

/obj/machinery/food_replicator/ownership()
	. = ..()
	. += owns(nameof(container), policy = OWN_CONTAINED)
