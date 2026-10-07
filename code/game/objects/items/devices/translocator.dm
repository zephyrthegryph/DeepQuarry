//The perfect adminboos device?
/obj/item/perfect_tele
	name = "personal translocator"
	desc = "Seems absurd, doesn't it? Yet, here we are. Allows the user to teleport themselves and others to a pre-set beacon."
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "hand_tele"
	w_class = ITEMSIZE_SMALL

	var/cell_type = /obj/item/cell/device/weapon
	var/obj/item/cell/power_source
	var/charge_cost = 800 // cell/device/weapon has 2400
	var/battery_lock = 0	//If set, weapon cannot switch batteries

	var/longrange = 0 //Can teleport very long distances
	var/abductor = 0 //Can be used on teleportation blocking turfs

	/// Relation list view: our beacons (see REL_LIST below).
	var/list/obj/item/perfect_tele_beacon/beacons
	var/loc_network = null //Used if you want to create pre-made beacons on the maps
	var/ready = 1
	var/beacons_left = 3
	var/failure_chance = 5 //Percent
	var/obj/item/perfect_tele_beacon/destination
	var/list/warned_users
	var/list/logged_events

	var/list/radial_images

	var/static/radial_plus = image(icon = 'icons/mob/radial_vr.dmi', icon_state = "tl_plus")
	var/static/radial_set = image(icon = 'icons/mob/radial_vr.dmi', icon_state = "tl_set")
	var/static/radial_seton = image(icon = 'icons/mob/radial_vr.dmi', icon_state = "tl_seton")

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	/// What a beacon is called, and what makes them, in the beacon menu's messages (a tome's pages).
	var/beacon_word = "beacon"
	var/maker_word = "translocator"
	/// The beacon a new one is made as.
	var/beacon_type = /obj/item/perfect_tele_beacon

TRACKED(/obj/item/perfect_tele, beacons_left)

CAPABILITIES(/obj/item/perfect_tele)
	ref_many(nameof(beacons))
	owns_one(nameof(power_source), /obj/item/cell, starts = nameof(cell_type))
	// held in the other hand, an empty hand takes the cell out (otherwise the click declines to pick up)
	op("unload", hand(), label("Remove cell"), then(PROC_REF(interaction_hand)))
	// the old attack_self: pick a beacon on the radial, or make a new one and name it
	op("choose_beacon", in_hand(), label("Choose beacon"),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(beacon_choices)), "radial" = TRUE, "tooltips" = TRUE, "autopick_single_option" = TRUE, "timeout" = 0), step = "beacon"),
		asks(/datum/prompt/text, fields = list("title" = "name", "question" = computed(PROC_REF(beacon_name_question)), "max_len" = 20, "name_text" = TRUE, "timeout" = 0), step = "name", when = PROC_REF(asks_beacon_name)),
		then(PROC_REF(beacon_chosen)))
	// a cell goes in; one of our own beacons goes back in
	op("load", inputs(item(/obj/item/cell), item(/obj/item/perfect_tele_beacon)), label("Insert"), then(PROC_REF(interaction_item)))

/obj/item/perfect_tele/Initialize(mapload)
	. = ..()

	flags |= NOBLUDGEON
	if(!power_source) // no cell_type
		rel_set(src, nameof(power_source), new /obj/item/cell/device(src)) // ALLOW(decl): fallback when a subtype clears cell_type
	rebuild_radial_images()

// Relation list view of beacons (a premade beacon may be listed by several translocators, so
// no pair); each beacon names its maker one-sided (tele_hand), cleared when the maker dies.

/// The beacon in `beacons` named `name`, or null.
/obj/item/perfect_tele/proc/find_beacon(name)
	for(var/obj/item/perfect_tele_beacon/B as anything in beacons)
		if(B.tele_name == name)
			return B
	return null

/// Adds the premade beacons of our loc_network (consumed on first use).
/obj/item/perfect_tele/proc/claim_network_beacons()
	if(!loc_network)
		return
	for(var/obj/item/perfect_tele_beacon/stationary/nb in REGISTRY_MEMBERS(REGISTRY_TELE_BEACONS_PREMADE))
		if(nb.tele_network == loc_network)
			rel_add(src, nameof(beacons), nb)
	loc_network = null //Consumed

DECLARE_APPEARANCE_PROC(/obj/item/perfect_tele, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/perfect_tele/appearance_overlays()
	. = list()
	if(!power_source)
		icon_state = "[initial(icon_state)]_o"
	else if(ready && (power_source.check_charge(charge_cost) || power_source.fully_charged()))
		icon_state = "[initial(icon_state)]"
	else
		icon_state = "[initial(icon_state)]_w"

	. += ..()

/obj/item/perfect_tele/proc/rebuild_radial_images()
	LAZYCLEARLIST(radial_images)

	var/index = 1
	for(var/obj/item/perfect_tele_beacon/beacon as anything in beacons)
		var/bcn = beacon.tele_name
		var/image/I = image(icon = 'icons/mob/radial_vr.dmi', icon_state = "tl_[index]")

		if(destination() == beacon)
			I.add_overlay(radial_seton)
		else
			I.add_overlay(radial_set)

		LAZYSET(radial_images, bcn, I)

		index++

	if(beacons_left)
		var/image/I = image(icon = 'icons/mob/radial_vr.dmi', icon_state = "tl_[index]")
		I.add_overlay(radial_plus)
		LAZYSET(radial_images, "New Beacon", I)

/obj/item/perfect_tele/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		unload_ammo(user)
		return OP_OK
	return OP_DECLINE

/// The radial's choices: our beacons (and the network's), and "New Beacon" while any are left.
/obj/item/perfect_tele/proc/beacon_choices(datum/act/A)
	claim_network_beacons()
	return radial_images

/obj/item/perfect_tele/proc/beacon_name_question(datum/act/op/A)
	return "New [beacon_word]'s name (2-20 char):"

/// The name step is asked after "New Beacon", while a beacon is left to make.
/obj/item/perfect_tele/proc/asks_beacon_name(datum/act/op/A)
	return A.step_value("beacon") == "New Beacon" && beacons_left > 0

/obj/item/perfect_tele/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	afterattack(M, user)

/obj/item/perfect_tele/proc/unload_ammo(mob/user, ignore_inactive_hand_check = 0)
	if(battery_lock)
		to_chat(user,span_notice("[src] does not have a battery port."))
		return
	if((user.get_inactive_hand() == src || ignore_inactive_hand_check) && power_source)
		to_chat(user,span_notice("You eject \the [power_source] from \the [src]."))
		user.put_in_hands(power_source)
		rel_take(src, nameof(power_source))
		update_icon()
	else
		to_chat(user,span_notice("[src] does not have a power cell."))

/obj/item/perfect_tele/proc/check_menu(mob/living/user)
	if(!istype(user))
		return FALSE
	if(user.incapacitated() || !user.Adjacent(src))
		return FALSE
	return TRUE

/// The chosen beacon becomes the destination; "New Beacon" makes one with the name given.
/obj/item/perfect_tele/proc/beacon_chosen(datum/act/op/A)
	var/mob/user = A.actor
	if(!(user.ckey in warned_users))
		LAZYOR(warned_users, user.ckey)
		tgui_alert_async(user,{"
This device can be easily used to break ERP preferences due to the nature of teleporting and tele-vore.
Make sure you carefully examine someone's OOC prefs before teleporting them if you are going to use this device for ERP purposes.
This device records all warnings given and teleport events for admin review in case of pref-breaking, so just don't do it.
"},"OOC Warning")
	var/choice = A.step_value("beacon")
	if(!choice || !check_menu(user))
		return OP_OK
	if(choice != "New Beacon")
		rel_set(src, nameof(destination), find_beacon(choice))
		rebuild_radial_images()
		return OP_OK
	if(beacons_left <= 0)
		to_chat(user, span_warning("The [maker_word] can't support any more [beacon_word]s!"))
		return OP_OK
	var/new_name = A.step_value("name")
	if(isnull(new_name))
		return OP_OK
	if(length(new_name) > 20 || length(new_name) < 2)
		to_chat(user, span_warning("Entered name length invalid (must be longer than 2, no more than than 20)."))
		return

	if(find_beacon(new_name))
		to_chat(user, span_warning("No duplicate names, please. '[new_name]' exists already."))
		return

	var/obj/item/perfect_tele_beacon/nb = new beacon_type(get_turf(src))
	nb.tele_name = new_name
	rel_set(nb, nameof(nb.tele_hand), src)
	nb.creator = user.ckey
	rel_add(src, nameof(beacons), nb)
	beacons_left--
	if(isliving(user))
		var/mob/living/L = user
		L.put_in_any_hand_if_possible(nb)
	rebuild_radial_images()
	return OP_OK


/// A cell goes in (with none in); one of our own beacons goes back in.
/obj/item/perfect_tele/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/W = A.held
	if(istype(W,cell_type) && !power_source)
		if(!move_into(src, nameof(src.power_source), W, user))
			return OP_OK
		power_source.update_icon() //Why doesn't a cell do this already? :|
		to_chat(user,span_notice("You insert \the [power_source] into \the [src]."))
		update_icon()

	else if(istype(W,/obj/item/perfect_tele_beacon))
		var/obj/item/perfect_tele_beacon/tb = W
		if(tb in beacons)
			var/beacon_name = "\the [tb]"
			if(!consume(tb, user))
				return OP_OK
			to_chat(user,span_notice("You re-insert [beacon_name] into \the [src]."))
			rel_remove(src, nameof(beacons), tb)
			set_beacons_left(beacons_left + 1)
		else
			to_chat(user,span_notice("\The [tb] doesn't belong to \the [src]."))
			return OP_OK
	else
		return OP_DECLINE
	return OP_OK

/obj/item/perfect_tele/proc/teleport_checks(mob/living/target,mob/living/user)
	//Uhhuh, need that power source
	if(!power_source)
		to_chat(user,span_warning("\The [src] has no power source!"))
		return FALSE

	//Check for charge
	if((!power_source.check_charge(charge_cost)) && (!power_source.fully_charged()))
		to_chat(user,span_warning("\The [src] does not have enough power left!"))
		return FALSE

	//Only mob/living need apply.
	if(!istype(user) || !istype(target))
		return FALSE

	//No, you can't teleport buckled people.
	if(target?.buckled_to())
		to_chat(user,span_warning("The target appears to be attached to something..."))
		return FALSE

	//No, you can't teleport if it's not ready yet.
	if(!ready)
		to_chat(user,span_warning("\The [src] is still recharging!"))
		return FALSE

	//No, you can't teleport if there's no destination.
	if(!destination())
		to_chat(user,span_warning("\The [src] doesn't have a current valid destination set!"))
		return FALSE

	//No, you can't teleport if there's a jammer.
	if(is_jammed(src) || is_jammed(destination()))
		var/area/our_area = get_area(src)
		if(!our_area.no_comms)	//I don't actually want this to block teleporters, just comms
			to_chat(user,span_warning("\The [src] refuses to teleport you, due to strong interference!"))
			return FALSE

	//No, you can't port to or from away missions. Stupidly complicated check.
	var/turf/uT = get_turf(user)
	var/turf/dT = get_turf(destination())
	var/list/dat = list()
	dat["z_level_detection"] = using_map.get_map_levels(uT.z)

	if(!uT || !dT)
		return FALSE

	if(!longrange)
		if( (uT.z != dT.z) && (!(dT.z in dat["z_level_detection"])) )
			to_chat(user,span_warning("\The [src] can't teleport you that far!"))
			return FALSE

	if(!abductor)
		if(uT.block_tele || dT.block_tele)
			to_chat(user,span_warning("Something is interfering with \the [src]!"))
			return FALSE

	//Seems okay to me!
	return TRUE

/obj/item/perfect_tele/afterattack(mob/living/target, mob/user, proximity_flag, click_parameters, stance = I_HURT, ignore_fail_chance = 0)
	//No, you can't teleport people from over there.
	if(!user.Adjacent(target) && !proximity_flag)
		return
	if(!istype(target))
		return

	if(!teleport_checks(target,user))
		return //The checks proc can send them a message if it wants.

	var/struggle = 0
	if(isliving(target))
		var/mob/living/L = target
		if(!L.stat)
			if(L != user)
				if(L.combat_mode || (L.ai_brain != null))
					to_chat(user, span_notice("[L] is resisting your attempt to teleport them with \the [src]."))
					to_chat(L, span_danger(" [user] is trying to teleport you with \the [src]!"))
					struggle = 3 SECONDS
	task_start(/datum/task/timed/translocate, user, target, duration = struggle, receiver = src, ignore_fail_chance = ignore_fail_chance)

/// Sending the target to the chosen beacon: at once, or after a struggle with someone resisting.
/datum/task/timed/translocate
	complete_proc = /obj/item/perfect_tele/proc/teleport_now
	var/ignore_fail_chance = 0

/obj/item/perfect_tele/proc/teleport_now(datum/task/timed/translocate/task)
	var/mob/living/target = task.target
	var/mob/user = task.actor
	var/ignore_fail_chance = task.ignore_fail_chance
	if(!ready || !destination() || !power_source)
		return
	//Bzzt.
	ready = 0
	power_source.use(charge_cost)

	//Unbuckle taur riders
	if(isliving(target))
		var/mob/living/L = target
		if(LAZYLEN(L?.buckled_mob_list()))
			var/datum/riding/R = L.riding_datum
			for(var/rider in L?.buckled_mob_list())
				R.force_dismount(rider)

	//Failure chance
	if (!ignore_fail_chance)
		if(prob(failure_chance) && length(beacons) >= 2)
			var/list/wrong_choices = beacons - destination()
			rel_set(src, nameof(destination), pick(wrong_choices))
			to_chat(user,span_warning("\The [src] malfunctions and sends you to the wrong beacon!"))

	//Destination beacon vore checking
	var/turf/dT = get_turf(destination())
	var/atom/real_dest = dT

	var/atom/real_loc = destination().loc
	if(isbelly(real_loc))
		real_dest = real_loc
	if(isliving(real_loc))
		var/mob/living/L = real_loc
		if(L.vore_selected)
			real_dest = L.vore_selected
		else if(length(L.vore_organs))
			real_dest = pick(L.vore_organs)

	//Confirm televore
	var/televored = FALSE
	if(isbelly(real_dest))
		var/obj/belly/B = real_dest
		if(target.devourable && target.can_be_drop_prey && B.owner != target)
			televored = TRUE
			to_chat(target, span_vwarning("\The [src] teleports you right into \a [lowertext(real_dest.name)]!"))
		else
			to_chat(target, span_vwarning("\The [src] narrowly avoids teleporting you right into \a [lowertext(real_dest.name)]!"))
			real_dest = dT //Nevermind!

	//Phase-out effect
	phase_out(target,get_turf(target))

	//Move them
	target.forceMove(real_dest)

	//Phase-in effect
	phase_in(target,get_turf(target))

	//And any friends!
	for(var/obj/item/grab/G in contents_of(target))
		var/mob/grabbed = G?.grab_target()
		if(grabbed && (G.state >= GRAB_AGGRESSIVE))

			//Phase-out effect for grabbed person
			phase_out(grabbed,get_turf(grabbed))

			//Move them, and televore if necessary
			grabbed.forceMove(real_dest)
			if(televored)
				to_chat(target,span_warning("\The [src] teleports you right into \a [lowertext(real_dest.name)]!"))

			//Phase-in effect for grabbed person
			phase_in(grabbed,get_turf(grabbed))

	update_icon()
	after(src, 30 SECONDS, PROC_REF(translocator_ready))

	LAZYSET(logged_events, "[world.time]", "[user] teleported [target] to [real_dest] [televored ? "(Belly: [lowertext(real_dest.name)])" : null]")

/obj/item/perfect_tele/proc/translocator_ready()
	ready = 1
	update_icon()

/obj/item/perfect_tele/proc/phase_out(mob/M,turf/T)

	if(!M || !T)
		return

	play_sfx(T, SFX_SPARKS)
	anim(T,M,'icons/mob/mob.dmi',,"phaseout",,M.dir)

/obj/item/perfect_tele/proc/phase_in(mob/M,turf/T)

	if(!M || !T)
		return

	fx_sparks(M, 5, FALSE)
	play_sfx(T, SFX_EFFECTS_PHASEIN, 0.25)
	play_sfx(T, SFX_EFFECTS_SPARKS2)
	anim(T,M,'icons/mob/mob.dmi',,"phasein",,M.dir)

/obj/item/perfect_tele_beacon
	name = "translocator beacon"
	desc = "That's unusual."
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "motion2"
	w_class = ITEMSIZE_TINY

	var/tele_name
	var/obj/item/perfect_tele/tele_hand
	var/creator
	var/list/warned_users
	var/tele_network = null
	flags = NOBLUDGEON

CAPABILITIES(/obj/item/perfect_tele_beacon)
	// the first pick-up of someone else's beacon warns first (otherwise the click declines to pick up)
	op("warn", hand(), label("Pick up"), asks(/datum/prompt/choice, fields = list("title" = "OOC Warning", "question" = computed(PROC_REF(warning_text)), "choices" = list("Take It", "Leave It"), "buttons" = TRUE, "timeout" = 0), when = PROC_REF(needs_warning)), then(PROC_REF(warning_answered)))
	// the old attack_self: eat the beacon, into a chosen belly, after a moment
	op("eat", in_hand(), label("Eat"), needs(req_actor_kind(/mob/living, because = /datum/msg/req_silent)),
		asks(/datum/prompt/choice, fields = list("title" = "Eat beacon?", "question" = "You COULD eat the beacon...", "choices" = list("Eat it!", "No, thanks."), "buttons" = TRUE, "timeout" = 0), step = "eat"),
		asks(/datum/prompt/choice, fields = list("title" = "Select A Belly", "question" = "Which belly?", "choices" = computed(PROC_REF(belly_choices)), "timeout" = 0), step = "belly", when = PROC_REF(asks_belly)),
		then(PROC_REF(belly_chosen)))

/// The warning is asked of someone who did not make the beacon and has not been warned.
/obj/item/perfect_tele_beacon/proc/needs_warning(datum/act/op/A)
	return tele_beacon_warns(src, A.actor)

/// The OOC warning before first picking up someone else's beacon.
/obj/item/perfect_tele_beacon/proc/warning_text(datum/act/op/A)
	return {"
This device is a translocator beacon. Having it on your person may mean that anyone
who teleports to this beacon gets teleported into your selected vore-belly. If you are prey-only
or don't wish to potentially have a random person teleported into you, it's suggested that you
not carry this around."}

/// Has `user` (who did not make `beacon`) still to be warned before picking it up?
/proc/tele_beacon_warns(obj/item/perfect_tele_beacon/beacon, mob/user)
	READS_FROM() // who made the beacon and who was warned are asked when the hand reaches for it
	return user.ckey != beacon.creator && !(user.ckey in beacon.warned_users)

/obj/item/perfect_tele_beacon/proc/warning_answered(datum/act/op/A)
	var/mob/user = A.actor
	if(!needs_warning(A))
		return OP_DECLINE
	LAZYOR(warned_users, user.ckey)
	var/datum/prompt/R = A.answer
	if(R?.value == "Take It")
		pick_up_by_hand(user) // the click this op answered: its own handler is running, so it cannot dispatch a second click
	return OP_OK

/obj/item/perfect_tele_beacon/stationary
	name = "stationary translocator beacon"
	icon = 'icons/obj/radio.dmi'
	icon_state = "floor_beacon"
	w_class = ITEMSIZE_HUGE
	anchored = TRUE

REGISTRY_MEMBERSHIP(/obj/item/perfect_tele_beacon/stationary, REGISTRY_TELE_BEACONS_PREMADE)

/obj/item/perfect_tele_beacon/proc/asks_belly(datum/act/op/A)
	return A.step_value("eat") == "Eat it!"

/obj/item/perfect_tele_beacon/proc/belly_choices(datum/act/op/A)
	var/mob/living/user = A.actor
	return user.vore_organs

/obj/item/perfect_tele_beacon/proc/belly_chosen(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/belly/bellychoice = A.step_value("belly")
	if(istype(bellychoice) && bellychoice.owner == user)
		act_message(user, src, MSG_SELF(span_notice("You begin putting %T% into your [bellychoice.name]!")), MSG_OTHERS(span_warning("%U% is trying to stuff %T% into [user.gender == MALE ? "his" : user.gender == FEMALE ? "her" : "their"] [bellychoice.name]!")))
		task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user, bellychoice))
	return OP_OK

/obj/item/perfect_tele_beacon/proc/attack_self_timed_done(mob/user, obj/belly/bellychoice)
	user.unEquip(src)
	forceMove(bellychoice)
	act_message(user, null, MSG_SELF("You eat the the beacon!"), MSG_OTHERS(span_warning("%U% eats a telebeacon!")))

// A single-beacon variant for use by miners (or whatever)
/obj/item/perfect_tele/one_beacon
	name = "mini-translocator"
	desc = "A more limited translocator with a single beacon, useful for some things, like setting the mining department on fire accidentally."
	icon_state = "minitrans"
	beacons_left = 1 //Just one
	cell_type = /obj/item/cell/device

/obj/item/perfect_tele/alien
	name = "alien translocator"
	desc = "This strange device allows one to teleport people and objects across large distances."
	icon_state = "alientele"

	cell_type = /obj/item/cell/device/weapon/recharge/alien
	charge_cost = 400
	beacons_left = 6
	failure_chance = 0 //Percent
	longrange = 1
	abductor = 1

/obj/item/perfect_tele/alien/bluefo
	name = "hybrid translocator"
	desc = "This strange device allows one to teleport people and objects across large distances. It has only a single preprogrammed destination, though."
	icon_state = "alientele"

	cell_type = /obj/item/cell/device/weapon/recharge/alien
	charge_cost = 400
	beacons_left = 0
	failure_chance = 0
	longrange = 1
	abductor = 1
	loc_network = "hybridshuttle"

/obj/item/perfect_tele/frontier
	icon_state = "frontiertrans"
	beacons_left = 1 //Just one
	battery_lock = 1
	unacidable = TRUE
	failure_chance = 0 //Percent

	var/phase_power = 75
	var/recharging = 0

/obj/item/perfect_tele/frontier/unload_ammo(mob/user, ignore_inactive_hand_check = 0)
	if(recharging)
		return
	recharging = 1
	update_icon()
	act_message(user, src, MSG_SELF(span_notice("You open %T% and start pumping the handle.")), \
		MSG_OTHERS(span_notice("%U% opens %T% and starts pumping the handle.")))
	pump_handle(user)

/// One second of pumping the handle per call, until the cell is full or the user stops.
/obj/item/perfect_tele/frontier/proc/pump_handle(mob/user)
	task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(pump_stroke), done_args = list(user), on_fail = PROC_REF(pump_done))

/obj/item/perfect_tele/frontier/proc/pump_stroke(mob/user)
	play_sfx(src, SFX_ITEMS_CHANGE_DRILL)
	if(!recharging || power_source.give(phase_power) < phase_power)
		pump_done()
		return
	pump_handle(user)

/obj/item/perfect_tele/frontier/proc/pump_done()
	recharging = 0
	update_icon()

DECLARE_APPEARANCE_PROC(/obj/item/perfect_tele/frontier, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/perfect_tele/frontier/appearance_overlays()
	. = list()
	if(recharging)
		icon_state = "[initial(icon_state)]_o"
		update_held_icon()
		return .
	. += ..()

/obj/item/perfect_tele/frontier/staff
	name = "centcom translocator"
	desc = "Similar to translocator technology, however, most of its destinations are hardcoded."
	charge_cost = 1200 // Enough for one person and their partner
	loc_network = "centcom"
	longrange = 1

/obj/item/perfect_tele/frontier/unknown
	name = "modified translocator"
	desc = "This crank-charged translocator has only one beacon, but it already has a destination preprogrammed into it."
	charge_cost = 1200 // Enough for one person and their partner
	longrange = 1
	abductor = 1

/obj/item/perfect_tele/frontier/unknown/one
	loc_network = "unkone"
/obj/item/perfect_tele/frontier/unknown/two
	loc_network = "unktwo"
/obj/item/perfect_tele/frontier/unknown/three
	loc_network = "unkthree"
/obj/item/perfect_tele/frontier/unknown/four
	loc_network = "unkfour"
/obj/item/perfect_tele/frontier/unknown/five
	loc_network = "unkfive"
/obj/item/perfect_tele/frontier/unknown/six
	loc_network = "unksix"

/// Relation view: destination (reads null once it is gone).
/obj/item/perfect_tele/proc/destination() as /obj/item/perfect_tele_beacon
	return destination

/// Relation view: tele hand (reads null once it is gone).
/obj/item/perfect_tele_beacon/proc/tele_hand() as /obj/item/perfect_tele
	return tele_hand
