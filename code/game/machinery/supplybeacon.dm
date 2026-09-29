// Used to deploy the bacon.
/obj/item/supply_beacon
	name = "inactive supply beacon"
	icon = 'icons/obj/supplybeacon.dmi'
	desc = "An inactive, hacked supply beacon stamped with the local system's Rapid Fabrication logo. Good for one (1) ballistic supply pod shipment."
	icon_state = "beacon"
	var/deploy_path = /obj/machinery/power/supply_beacon
	var/deploy_time = 30

/obj/item/supply_beacon/supermatter
	name = "inactive supermatter supply beacon"
	deploy_path = /obj/machinery/power/supply_beacon/supermatter

DECLARE_INTERACTIONS(/obj/item/supply_beacon, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/supply_beacon/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " begins setting up %T%."))
	om_task_timed(user, deploy_time, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user))
	return TRUE

/obj/item/supply_beacon/proc/attack_self_timed_done(mob/user)
	var/obj/S = new deploy_path(get_turf(user))
	act_message(user, S, others = span_infoplain(span_bold("%U%") + " deploys %T%."))
	consume(src, user)

/obj/machinery/power/supply_beacon
	silicon_use = ROBOT_USE_HAND_ADJACENT
	name = "supply beacon"
	desc = "A bulky moonshot supply beacon. Someone has been messing with the wiring."
	icon = 'icons/obj/supplybeacon.dmi'
	icon_state = "beacon"

	anchored = FALSE
	density = TRUE
	layer = MOB_LAYER - 0.1
	stat = 0

	/// om_after() timer that sends the drop once the beacon has stayed powered for drop_delay, or 0.
	var/tmp/drop_timer = 0
	var/drop_delay = 450
	var/expended
	var/drop_type

/obj/machinery/power/supply_beacon/Initialize(mapload)
	. = ..()
	if(!drop_type) drop_type = pick(GLOB.supply_drop)

/obj/machinery/power/supply_beacon/supermatter
	name = "supermatter supply beacon"
	drop_type = "supermatter"

/obj/machinery/power/supply_beacon/wrench_act(mob/user, obj/item/tool)
	if(use_power)
		return ITEM_INTERACT_BLOCKING
	if(!anchored && !connect_to_network())
		to_chat(user, span_warning("This device must be placed over an exposed cable."))
		return ITEM_INTERACT_BLOCKING
	set_anchored(!anchored)
	act_message(user, src, others = span_notice("%U% [anchored ? "secures" : "unsecures"] %T%."))
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/supply_beacon/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/supply_beacon_use,
	)
	..()

/// Old attack_hand, which never called ..() (ungated: no machinery hand gate).
/datum/interaction/machine_hand/ungated/supply_beacon_use
	id = "supply_beacon_use"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/power/supply_beacon/proc/interaction_use

/obj/machinery/power/supply_beacon/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(expended)
		set_use_power(USE_POWER_OFF)
		to_chat(user, span_warning("\The [src] has used up its charge."))
		return TRUE
	if(anchored)
		if(use_power)
			deactivate(user)
		else
			activate(user)
		return TRUE
	to_chat(user, span_warning("You need to secure the beacon with a wrench first!"))
	return TRUE

/obj/machinery/power/supply_beacon/proc/activate(mob/user)
	if(expended)
		return
	if(surplus() < 500)
		if(user) to_chat(user, span_notice("The connected wire doesn't have enough current."))
		return
	set_light(3, 3, "#00CCAA")
	icon_state = "beacon_active"
	set_use_power(USE_POWER_IDLE)
	if(user) to_chat(user, span_notice("You activate the beacon. The supply drop will be dispatched soon."))

/obj/machinery/power/supply_beacon/proc/deactivate(mob/user, permanent)
	if(permanent)
		expended = 1
		icon_state = "beacon_depleted"
	else
		icon_state = "beacon"
	set_light(0)
	set_use_power(USE_POWER_OFF)
	if(drop_timer)
		om_cancel_timer(src, drop_timer)
		drop_timer = 0
	if(user) to_chat(user, span_notice("You deactivate the beacon."))

// an active beacon deactivates.
/obj/machinery/power/supply_beacon/on_destroy(force)
	if(use_power)
		deactivate()
	..()

/obj/machinery/power/supply_beacon/machine_step()
	if(expended)
		return PROCESS_KILL
	if(!use_power)
		return
	if(draw_power(500) < 500)
		deactivate()
		return
	if(!drop_timer)
		drop_timer = om_after(src, drop_delay, PROC_REF(drop_timer_fired))

/// om_after() callback: the beacon stayed powered for drop_delay, so the pod is sent.
/obj/machinery/power/supply_beacon/proc/drop_timer_fired()
	drop_timer = 0
	if(expended || !use_power)
		return
	deactivate(permanent = 1)
	var/drop_x = src.x - 2
	var/drop_y = src.y - 2
	var/drop_z = src.z
	GLOB.command_announcement.Announce("[using_map.starsys_name] Rapid Fabrication priority supply request #[rand(1000,9999)]-[rand(100,999)] received. Shipment dispatched via ballistic supply pod for immediate delivery. Have a nice day.", "Thank You For Your Patronage")
	om_after(src, rand(100, 300), PROC_REF(drop_supply), drop_x, drop_y, drop_z)

/obj/machinery/power/supply_beacon/proc/drop_supply(drop_x, drop_y, drop_z)
	new /datum/random_map/droppod/supply(null, drop_x, drop_y, drop_z, supplied_drop = drop_type) // Splat.
