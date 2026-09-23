//Cloning revival method.
//The pod handles the actual cloning while the computer manages the clone profiles

//Potential replacement for genetics revives or something I dunno (?)

//Find a dead mob with a brain and client.
/proc/find_dead_player(find_key)
	if(isnull(find_key))
		return

	var/mob/selected = null
	for(var/mob/living/M in GLOB.player_list)
		//Dead people only thanks!
		if((M.stat != 2) || (!M.client))
			continue
		//They need a brain!
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(!H.has_brain())
				continue
		if(M.ckey == find_key)
			selected = M
			break
	return selected

#define MINIMUM_HEAL_LEVEL 40
// Clone growth runs on genetic damage (0..100). The old pool was 1.5x endurance
// deep; growth rates are scaled by this so cycles take as long as before.
#define DQ_CLONE_GROWTH_SCALE 1.5
// Genetic damage above which the pod refuses an early unlock (old: health < -20).
#define DQ_CLONE_UNLOCK_LOAD 80
// Genetic damage a resleeving pod grows a new sleeve out of (old: 0.75x endurance).
#define DQ_SLEEVE_GROWTH_LOAD 75

/obj/machinery/clonepod
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "cloning pod"
	desc = "An electronically-lockable pod for growing organic tissue."
	density = TRUE
	anchored = TRUE
	flags = REMOTEVIEW_ON_ENTER
	circuit = /obj/item/circuitboard/clonepod
	icon = 'icons/obj/cloning.dmi'
	icon_state = "pod_0"
	req_access = list(ACCESS_GENETICS) // For premature unlocking.
	VAR_PRIVATE/datum/weakref/weakref_occupant = null
	var/heal_level = 20				// Growth quality: the clone is released once its genetic damage falls to clone_release_load().
	var/heal_rate = 1
	var/locked = 0
	var/obj/machinery/computer/cloning/connected = null //So we remember the connected clone machine.
	var/mess = 0					// Need to clean out it if it's full of exploded clone.
	var/attempting = 0				// One clone attempt at a time thanks
	var/eject_wait = 0				// Don't eject them as soon as they are created fuckkk

	var/list/containers = list()	// Beakers for our liquid biomass
	var/container_limit = 3			// How many beakers can the machine hold?

	var/speed_coeff
	var/efficiency

/obj/machinery/clonepod/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()

/obj/machinery/clonepod/Destroy()
	for(var/obj/container in containers)
		UnregisterSignal(container, COMSIG_QDELETING)
		container.forceMove(get_turf(src))
	containers.Cut()
	locked = FALSE
	go_out()
	. = ..()

/obj/machinery/clonepod/proc/set_occupant(mob/living/L)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!L)
		weakref_occupant = null
		STOP_MACHINE_PROCESSING(src)
		return
	weakref_occupant = WEAKREF(L)
	START_MACHINE_PROCESSING(src)

/obj/machinery/clonepod/proc/get_occupant()
	RETURN_TYPE(/mob/living)
	SHOULD_NOT_OVERRIDE(TRUE)
	return weakref_occupant?.resolve()

/obj/machinery/clonepod/attack_ai(mob/user as mob)

	add_hiddenprint(user)
	return attack_hand(user)

/obj/machinery/clonepod/attack_hand(mob/user as mob)
	var/mob/living/occupant = get_occupant()
	if((isnull(occupant)) || (stat & NOPOWER))
		return
	if((!isnull(occupant)) && (occupant.stat != 2))
		to_chat(user, "Current clone cycle is [round(get_completion())]% complete.")
	return

//Start growing a human clone in the pod!
/obj/machinery/clonepod/proc/growclone(datum/transhuman/body_record/BR)
	if(mess || attempting)
		return 0
	var/datum/mind/clonemind = locate(BR.mydna.mind)

	if(!istype(clonemind, /datum/mind))	//not a mind
		return 0
	if(clonemind.current && clonemind.current.stat != DEAD)	//mind is associated with a non-dead body
		return 0
	if(clonemind.active)	//somebody is using that mind
		if(ckey(clonemind.key) != BR.ckey)
			return 0
	else
		for(var/mob/observer/dead/G in GLOB.player_list)
			if(G.ckey == BR.ckey)
				if(G.can_reenter_corpse)
					break
				else
					return 0

	if(clonemind.get_identity()?.has_genetic_modifier(/datum/modifier/no_clone))	//Can't be cloned: a persistent trait of the character
		return 0

	// Remove biomass when the cloning is started, rather than when the guy pops out
	remove_biomass(CLONE_BIOMASS)

	attempting = 1 //One at a time!!
	locked = 1

	eject_wait = 1
	addtimer(CALLBACK(src, PROC_REF(clear_eject_wait), BR, clonemind), 30, TIMER_DELETE_ME)

/obj/machinery/clonepod/proc/clear_eject_wait(datum/transhuman/body_record/BR, datum/mind/clonemind)
	eject_wait = 0

	//Get the clone body ready, let's calculate their health so the pod doesn't immediately eject them!!!
	var/mob/living/carbon/human/H = BR.produce_human_mob(src,FALSE, FALSE, "clone ([rand(0,999)])")
	SEND_SIGNAL(H, COMSIG_HUMAN_DNA_FINALIZED)

	//Get the clone body ready: a fresh clone is saturated with genetic damage and
	// the pod grows it out. Seeded directly (not injure()) so the fresh body
	// doesn't roll cellular-damage limb mutations.
	H.body.afflict(/datum/affliction/genetic_damage, null, AFFLICTION_SEVERITY_TERMINAL)
	H.Paralyse(4)
	H.Sleeping(4)
	H.set_cloned_appearance()

	// Move mind to body along with key
	transfer_mind(clonemind, H, "cloned from a body record", force = TRUE)
	to_chat(H, span_warning(span_bold("Consciousness slowly creeps over you as your body regenerates.") + "<br>" + span_bold(span_large("Your recent memories are fuzzy, and it's hard to remember anything from today...")) + \
		"<br>" + span_notice(span_italics("So this is what cloning feels like?"))))

	// A modifier is added which makes the new clone be unrobust.
	// Upgraded cloners can reduce the time of the modifier, up to 80%
	var/modifier_lower_bound = 25 MINUTES
	var/modifier_upper_bound = 40 MINUTES

	var/clone_sickness_length = abs(((heal_level - 20) / 100 ) - 1)
	clone_sickness_length = between(0.2, clone_sickness_length, 1.0) // Caps it off just incase.
	modifier_lower_bound = round(modifier_lower_bound * clone_sickness_length, 1)
	modifier_upper_bound = round(modifier_upper_bound * clone_sickness_length, 1)

	H.add_modifier(H.species.cloning_modifier, rand(modifier_lower_bound, modifier_upper_bound))
	H.add_modifier(/datum/modifier/cloned)

	// Finished!
	update_icon()
	set_occupant(H)
	attempting = 0

	return 1

//Grow clones to maturity then kick them out.  FREELOADERS
/obj/machinery/clonepod/process()
	var/mob/living/occupant = get_occupant()
	if(stat & NOPOWER) //Autoeject if power is lost
		if(occupant)
			locked = 0
			go_out()
		return PROCESS_KILL

	if((occupant) && (occupant.loc == src))
		if((occupant.stat == DEAD) || (occupant.suiciding) || !occupant.key)  //Autoeject corpses and suiciding dudes.
			locked = 0
			go_out()
			connected_message("Clone Rejected: Deceased.")
			return

		else if(clone_growth_load(occupant) > clone_release_load())
			occupant.Paralyse(4)
			occupant.Sleeping(4)

			//Slowly get that clone healed and finished.
			occupant.mend(TREAT_GENETIC_REPAIR, (2 * heal_rate) / DQ_CLONE_GROWTH_SCALE)

			//Premature clones may have brain damage.
			occupant.mend(TREAT_NEURAL_REPAIR, CEILING(0.5*heal_rate, 1))

			//So clones don't die of oxyloss in a running pod.
			if(occupant.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) < 30)
				occupant.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 60)
			occupant.Sleeping(30)
			//Also oxygenate ourselves because inaprovaline is so bad at preventing hypoxia!!
			occupant.mend(TREAT_OXYGENATION, 4)

			use_power(7500) //This might need tweaking.
			return

		else if(!eject_wait)
			playsound(src, 'sound/machines/medbayscanner1.ogg', 50, 1)
			audible_message("\The [src] signals that the cloning process is complete.", runemessage = "ding")
			connected_message("Cloning Process Complete.")
			locked = 0
			go_out()
			return

	else if((!occupant) || (occupant.loc != src))
		set_occupant(null)
		if(locked)
			locked = 0
		return PROCESS_KILL

	return

//Let's unlock this early I guess.  Might be too early, needs tweaking.
/obj/machinery/clonepod/attackby(obj/item/W as obj, mob/user as mob)
	var/mob/living/occupant = get_occupant()
	if(isnull(occupant))
		if(default_part_replacement(user, W))
			return
	if(istype(W, /obj/item/card/id)||istype(W, /obj/item/pda))
		if(!check_access(W))
			to_chat(user, span_warning("Access Denied."))
			return
		if((!locked) || (isnull(occupant)))
			return
		if((clone_growth_load(occupant) > DQ_CLONE_UNLOCK_LOAD) && (occupant.stat != DEAD))
			to_chat(user, span_warning("Access Refused."))
			return
		else
			locked = 0
			to_chat(user, "System unlocked.")
	else if(istype(W,/obj/item/reagent_containers/glass))
		if(LAZYLEN(containers) >= container_limit)
			to_chat(user, span_warning("\The [src] has too many containers loaded!"))
		else if(do_after(user, 1 SECOND, target = src))
			user.visible_message("[user] has loaded \the [W] into \the [src].", "You load \the [W] into \the [src].")
			track_biomass_container(W)
			user.drop_item()
			W.forceMove(src)
		return
	else
		..()

/obj/machinery/clonepod/screwdriver_act(mob/user, obj/item/tool)
	if(get_occupant())
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/clonepod/crowbar_act(mob/user, obj/item/tool)
	if(get_occupant())
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/clonepod/wrench_act(mob/user, obj/item/tool)
	var/mob/living/occupant = get_occupant()
	if(locked && (anchored || occupant))
		to_chat(user, span_warning("Can not do that while [src] is in use."))
		return ITEM_INTERACT_BLOCKING
	if(anchored)
		anchored = FALSE
		if(connected)
			connected.pods -= src
			connected = null
	else
		anchored = TRUE
	playsound(src, tool.usesound, 100, TRUE)
	user.visible_message("[user] [anchored ? "secures" : "unsecures"] [src] to the floor.", "You [anchored ? "secure" : "unsecure"] [src] to the floor.")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/clonepod/multitool_act(mob/user, obj/item/tool)
	if(!istype(tool, /obj/item/multitool))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	multitool.connecting = src
	to_chat(user, span_notice("You load connection data from [src] to [multitool]."))
	multitool.update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/clonepod/emag_act(remaining_charges, mob/user)
	if(isnull(get_occupant()))
		return
	to_chat(user, "You force an emergency ejection.")
	locked = 0
	go_out()
	return 1

//Put messages in the connected computer's temp var for display.
/obj/machinery/clonepod/proc/connected_message(message)
	if((isnull(connected)) || (!istype(connected, /obj/machinery/computer/cloning)))
		return 0
	if(!message)
		return 0

	connected.temp = "[name] : [message]"
	return 1

/obj/machinery/clonepod/RefreshParts()
	..()
	speed_coeff = 0
	efficiency = 0
	for(var/obj/item/stock_parts/scanning_module/S in component_parts)
		efficiency += S.rating
	for(var/obj/item/stock_parts/manipulator/P in component_parts)
		speed_coeff += P.rating
	heal_level = max(min((efficiency * 15) + 10, 100), MINIMUM_HEAL_LEVEL)

/// Genetic damage still to grow out of the clone (0..100).
/obj/machinery/clonepod/proc/clone_growth_load(mob/living/occupant)
	return occupant ? occupant.injury_load(INJURY_CATEGORY_GENETIC) : 0

/// The clone is released once its genetic damage falls to this. Better
/// scanners (higher heal_level) grow the clone out further before release:
/// heal_level 20 releases at ~53, heal_level 100 only when fully grown.
/obj/machinery/clonepod/proc/clone_release_load()
	return clamp((100 - heal_level) / DQ_CLONE_GROWTH_SCALE, 0, AFFLICTION_SEVERITY_TERMINAL)

/obj/machinery/clonepod/proc/get_completion()
	var/mob/living/occupant = get_occupant()
	if(!occupant)
		return 0
	var/span = AFFLICTION_SEVERITY_TERMINAL - clone_release_load()
	if(span <= 0)
		return 100
	return clamp(100 * (AFFLICTION_SEVERITY_TERMINAL - clone_growth_load(occupant)) / span, 0, 100)

/obj/machinery/clonepod/verb/eject()
	set name = "Eject Cloner"
	set category = "Object"
	set src in oview(1)

	if(usr.stat != 0)
		return
	go_out()
	add_fingerprint(usr)
	return

/obj/machinery/clonepod/proc/go_out()
	if(locked)
		return

	if(mess) //Clean that mess and dump those gibs!
		mess = 0
		gibs(src.loc)
		update_icon()
		return

	var/mob/living/occupant = get_occupant()
	if(!(occupant))
		return

	occupant.forceMove(get_turf(src))
	eject_wait = 0 //If it's still set somehow.
	if(ishuman(occupant)) //Need to be safe.
		var/mob/living/carbon/human/patient = occupant
		if(!(patient.species.flags & NO_DNA)) //If, for some reason, someone makes a genetically-unalterable clone, let's not make them permanently disabled.
			domutcheck(occupant) //Waiting until they're out before possible transforming.
			occupant.UpdateAppearance()
	set_occupant(null)

	update_icon()
	return

// Returns the total amount of biomass reagent in all of the pod's stored containers
/obj/machinery/clonepod/proc/get_biomass()
	var/biomass_count = 0
	if(LAZYLEN(containers))
		for(var/obj/item/reagent_containers/glass/G in containers)
			for(var/datum/reagent/R in G.reagents.reagent_list)
				if(R.id == REAGENT_ID_BIOMASS)
					biomass_count += R.volume

	return biomass_count

// Removes [amount] biomass, spread across all containers. Doesn't have any check that you actually HAVE enough biomass, though.
/obj/machinery/clonepod/proc/remove_biomass(amount = CLONE_BIOMASS)		//Just in case it doesn't get passed a new amount, assume one clone
	var/to_remove = 0	// Tracks how much biomass has been found so far
	if(LAZYLEN(containers))
		for(var/obj/item/reagent_containers/glass/G in containers)
			if(to_remove < amount)	//If we have what we need, we can stop. Checked every time we switch beakers
				for(var/datum/reagent/R in G.reagents.reagent_list)
					if(R.id == REAGENT_ID_BIOMASS)		// Finds Biomass
						var/need_remove = max(0, amount - to_remove)	//Figures out how much biomass is in this container
						if(R.volume >= need_remove)						//If we have more than enough in this beaker, only take what we need
							R.remove_self(need_remove)
							to_remove = amount
						else											//Otherwise, take everything and move on
							to_remove += R.volume
							R.remove_self(R.volume)
					else
						continue
			else
				return 1
	return 0

// Empties all of the beakers from the cloning pod, used to refill it
/obj/machinery/clonepod/verb/empty_beakers()
	set name = "Eject Beakers"
	set category = "Object"
	set src in oview(1)

	if(usr.stat != 0)
		return

	add_fingerprint(usr)
	drop_beakers()
	return

// Actually does all of the beaker dropping
// Returns 1 if it succeeds, 0 if it fails. Added in case someone wants to add messages to the user.
/obj/machinery/clonepod/proc/drop_beakers()
	if(LAZYLEN(containers))
		var/turf/T = get_turf(src)
		if(T)
			for(var/obj/item/reagent_containers/glass/G in containers)
				UnregisterSignal(G, COMSIG_QDELETING)
				G.forceMove(T)
				containers -= G
		return	1
	return 0

/obj/machinery/clonepod/proc/malfunction()
	var/mob/living/occupant = get_occupant()
	if(occupant)
		connected_message("Critical Error!")
		mess = 1
		update_icon()
		occupant.ghostize()
		QDEL_IN(occupant, 0.5 SECONDS)

/obj/machinery/clonepod/relaymove(mob/user)
	if(user.stat)
		return
	go_out()

/obj/machinery/clonepod/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || !(prob(100/severity)))
		return
	malfunction()
	..()

/obj/machinery/clonepod/explosion_contents_severity(severity)
	return severity

/obj/machinery/clonepod/update_icon()
	..()
	icon_state = "pod_0"
	if(get_occupant() && !(stat & NOPOWER))
		icon_state = "pod_1"
	else if(mess)
		icon_state = "pod_g"


/obj/machinery/clonepod/full/Initialize(mapload)
	. = ..()
	for(var/i = 1 to container_limit)
		track_biomass_container(new /obj/item/reagent_containers/glass/bottle/biomass(src))

/obj/machinery/clonepod/proc/track_biomass_container(obj/item/reagent_containers/glass/container)
	if(!container || (container in containers))
		return
	containers += container
	RegisterSignal(container, COMSIG_QDELETING, PROC_REF(on_biomass_container_qdel))

/obj/machinery/clonepod/proc/on_biomass_container_qdel(obj/item/reagent_containers/glass/container)
	SIGNAL_HANDLER
	containers -= container

//Health Tracker Implant

/obj/item/implant/health
	name = "health implant"
	known_implant = TRUE
	var/healthstring = ""

/obj/item/implant/health/proc/sensehealth()
	if(!implanted)
		return "ERROR"
	else
		if(isliving(implanted))
			var/mob/living/L = implanted
			healthstring = "[round(L.oxygen_debt())] - [round(L.injury_load(INJURY_CATEGORY_THERMAL))] - [round(L.injury_load(INJURY_CATEGORY_TOXIC))] - [round(L.injury_load(INJURY_CATEGORY_PHYSICAL))]"
		if(!healthstring)
			healthstring = "ERROR"
		return healthstring

#undef MINIMUM_HEAL_LEVEL

/*
 *	Diskette Box
 */

/obj/item/storage/box/disks
	name = "Diskette Box"
	icon_state = "disk_kit"

/obj/item/storage/box/disks/Initialize(mapload)
	. = ..()
	new /obj/item/disk/body_record(src)
	new /obj/item/disk/body_record(src)
	new /obj/item/disk/body_record(src)
	new /obj/item/disk/body_record(src)
	new /obj/item/disk/body_record(src)
	new /obj/item/disk/body_record(src)
	new /obj/item/disk/body_record(src)

/*
 *	Manual -- A big ol' manual.
 */

/obj/item/paper/Cloning
	name = "H-87 Cloning Apparatus Manual"
	info = {"<h4>Getting Started</h4>
	Congratulations, your station has purchased the H-87 industrial cloning device!<br>
	Using the H-87 is almost as simple as brain surgery! Simply insert the target humanoid into the scanning chamber and select the scan option to create a new profile!<br>
	<b>That's all there is to it!</b><br>
	<i>Notice, cloning system cannot scan inorganic life or small primates.  Scan may fail if subject has suffered extreme brain damage.</i><br>
	<p>Clone profiles may be viewed through the profiles menu. Scanning implants a complementary HEALTH MONITOR IMPLANT into the subject, which may be viewed from each profile.
	Profile Deletion has been restricted to \[Station Head\] level access.</p>
	<h4>Cloning from a profile</h4>
	Cloning is as simple as pressing the CLONE option at the bottom of the desired profile.<br>
	Per your company's EMPLOYEE PRIVACY RIGHTS agreement, the H-87 has been blocked from cloning crewmembers while they are still alive.<br>
	<br>
	<p>The provided CLONEPOD SYSTEM will produce the desired clone.  Standard clone maturation times (With SPEEDCLONE technology) are roughly 90 seconds.
	The cloning pod may be unlocked early with any \[Medical Researcher\] ID after initial maturation is complete.</p><br>
	<i>Please note that resulting clones may have a small DEVELOPMENTAL DEFECT as a result of genetic drift.</i><br>
	<h4>Profile Management</h4>
	<p>The H-87 (as well as your station's standard genetics machine) can accept STANDARD DATA DISKETTES.
	These diskettes are used to transfer genetic information between machines and profiles.
	A load/save dialog will become available in each profile if a disk is inserted.</p><br>
	<i>A good diskette is a great way to counter aforementioned genetic drift!</i><br>
	<br>"} + span_small("This technology produced under license from Thinktronic Systems, LTD.")

//SOME SCRAPS I GUESS
/* EMP grenade/spell effect
		if(istype(A, /obj/machinery/clonepod))
			A:malfunction()
*/
