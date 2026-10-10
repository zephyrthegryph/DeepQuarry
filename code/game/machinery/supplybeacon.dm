// Used to deploy the bacon.
/obj/item/supply_beacon
	name = "inactive supply beacon"
	icon = 'icons/obj/supplybeacon.dmi'
	desc = "An inactive, hacked supply beacon stamped with the local system's Rapid Fabrication logo. Good for one (1) ballistic supply pod shipment."
	icon_state = "beacon"
	var/deploy_path = /obj/machinery/power/supply_beacon
	var/deploy_time = 3 SECONDS

/obj/item/supply_beacon/supermatter
	name = "inactive supermatter supply beacon"
	deploy_path = /obj/machinery/power/supply_beacon/supermatter

CAPABILITIES(/obj/item/supply_beacon)
	op("self", in_hand(), starts(PROC_REF(interaction_self)), wait(PROC_REF(deployment_duration)), then(PROC_REF(attack_self_timed_done)))

/obj/item/supply_beacon/proc/deployment_duration(datum/act/op/A)
	return deploy_time

/// Old attack_self.
/obj/item/supply_beacon/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " begins setting up %T%."))
	return TRUE

/obj/item/supply_beacon/proc/attack_self_timed_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/S = new deploy_path(get_turf(user))
	act_message(user, S, others = span_infoplain(span_bold("%U%") + " deploys %T%."))
	consume(src, user)

/obj/machinery/power/supply_beacon
	name = "supply beacon"
	desc = "A bulky moonshot supply beacon. Someone has been messing with the wiring."
	icon = 'icons/obj/supplybeacon.dmi'
	icon_state = "beacon"

	anchored = FALSE
	density = TRUE
	layer = MOB_LAYER - 0.1

	/// after() timer that sends the drop once the beacon has stayed powered for drop_delay, or 0.
	var/drop_delay = 450
	var/drop_type

/// Spent: the drop was sent, the beacon never works again.
/obj/machinery/power/supply_beacon/var/expended = FALSE
TRACKED_BRIDGED(/obj/machinery/power/supply_beacon, expended, CHANGE_MACHINE_SETTINGS)
/// Draws power (and arms the drop) while switched on and not yet spent.
CAPABILITIES(/obj/machinery/power/supply_beacon)
	silicon_hand(adjacent = TRUE)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = cond_all(nameof(use_power), cond_not(nameof(expended))), wakes_on = list(nameof(use_power), nameof(expended)))
	rolls(nameof(drop_type), PROC_REF(roll_drop_type), when = cond_not(nameof(drop_type)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), label("Secure"), then(PROC_REF(wrench_used)))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/machinery/power/supply_beacon/proc/roll_drop_type(datum/roller/R)
	return R.choose(GLOB.supply_drop)

/obj/machinery/power/supply_beacon/supermatter
	name = "supermatter supply beacon"
	drop_type = "supermatter"

/// The wrench: secures the beacon over an exposed cable, or unsecures it (a running beacon takes the click and does nothing).
/obj/machinery/power/supply_beacon/proc/wrench_used(datum/act/op/A)
	var/obj/item/tool = A.held
	if(use_power)
		return OP_OK
	if(!anchored && !connect_to_network())
		to_chat(A.actor, span_warning("This device must be placed over an exposed cable."))
		return OP_OK
	set_anchored(!anchored)
	act_message(A.actor, src, others = span_notice("%U% [anchored ? "secures" : "unsecures"] %T%."))
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK

/obj/machinery/power/supply_beacon/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
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
		set_expended(TRUE)
		icon_state = "beacon_depleted"
	else
		icon_state = "beacon"
	set_light(0)
	set_use_power(USE_POWER_OFF)
	cancel_after(src, "drop")
	if(user) to_chat(user, span_notice("You deactivate the beacon."))

// an active beacon deactivates.
/obj/machinery/power/supply_beacon/on_destroy(force)
	if(use_power)
		deactivate()
	..()

/obj/machinery/power/supply_beacon/proc/work_step(datum/act/timer/A)
	if(draw_power(500) < 500)
		deactivate()
		return
	if(!after_pending(src, "drop"))
		after(src, drop_delay, PROC_REF(drop_timer_fired), key = "drop")

/// The keyed timer: the beacon stayed powered for drop_delay, so the pod is sent.
/obj/machinery/power/supply_beacon/proc/drop_timer_fired()
	if(expended || !use_power)
		return
	deactivate(permanent = 1)
	var/drop_x = src.x - 2
	var/drop_y = src.y - 2
	var/drop_z = src.z
	GLOB.command_announcement.Announce("[using_map.starsys_name] Rapid Fabrication priority supply request #[rand(1000,9999)]-[rand(100,999)] received. Shipment dispatched via ballistic supply pod for immediate delivery. Have a nice day.", "Thank You For Your Patronage")
	after(src, rand(10 SECONDS, 30 SECONDS), PROC_REF(drop_supply), with = list(drop_x, drop_y, drop_z))

/obj/machinery/power/supply_beacon/proc/drop_supply(drop_x, drop_y, drop_z)
	new /datum/random_map/droppod/supply(null, drop_x, drop_y, drop_z, supplied_drop = drop_type) // Splat.
