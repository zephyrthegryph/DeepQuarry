//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

//  Beacon randomly spawns in space
//	When a non-traitor (no special role in /mind) uses it, he is given the choice to become a traitor
//	If he accepts there is a random chance he will be accepted, rejected, or rejected and killed
//	Bringing certain items can help improve the chance to become a traitor

/obj/machinery/syndicate_beacon
	name = "ominous beacon"
	desc = "This looks suspicious..."
	icon = 'icons/obj/device.dmi'
	icon_state = "syndbeacon"
	anchored = TRUE
	density = TRUE
	var/temptext = ""
	var/selfdestructing = 0
	var/charges = 1



CAPABILITIES(/obj/machinery/syndicate_beacon)
	extend(TAG_UI, needs(req(PROC_REF(topic_usable), because = MSG(op/topic_gate))))
	op("beacon_talk", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(topic_usable), because = MSG(op/topic_gate))), asks(/datum/prompt/choice/syndicate_beacon, fields = list("title" = "Ominous Beacon", "buttons" = TRUE, "timeout" = 0)), then(PROC_REF(beacon_offer_answered)))

/datum/prompt/choice/syndicate_beacon/prepare(datum/act/A)
	..()
	var/obj/machinery/syndicate_beacon/B = owner
	var/mob/user = answerer
	user.set_machine(B)
	var/message = "Scanning [pick("retina pattern", "voice print", "fingerprints", "dna sequence")]... Identity confirmed.\n"
	var/can_traitor = FALSE
	if(ishuman(user) || isAI(user))
		if(is_special_character(user))
			message += "Operative record found. Greetings, Agent [user.name]."
		else if(B.charges < 1)
			message += "Connection severed."
		else
			var/honorific = (user.gender == FEMALE) ? "Ms." : "Mr."
			message += "Identity not found in operative database. What can the Syndicate do for you today, [honorific] [user.name]?"
			can_traitor = !B.selfdestructing
	if(length(B.temptext))
		message += "\n\n[B.temptext]"
	if(can_traitor)
		var/offer = pick("I want to switch teams.", "I want to work for you.", "Let me join you.", "I can be of use to you.", "You want me working for you, and here's why...", "Give me an objective.", "How's the 401k over at the Syndicate?")
		choices = list(offer, "Hang up")
	else
		choices = list("Hang up")
	question = message

/obj/machinery/syndicate_beacon/proc/beacon_offer_answered(datum/act/op/A)
	if(!A.answer || A.answer.value == "Hang up")
		return
	var/mob/user = A.actor
	betraitor(user, user)

/// The only button of the second window ends the call.
/obj/machinery/syndicate_beacon/proc/beacon_hung_up(datum/act/request/A)
	return

/// Offers `M` (who must be `user`) a traitor role; the beacon's accept path.
/obj/machinery/syndicate_beacon/proc/betraitor(mob/user, mob/M)
	if(charges < 1)
		updateUsrDialog(user)
		return
	if(!istype(M) || M != user) // self-only: nobody accepts for someone else
		return
	if(M.mind?.special_role || jobban_isbanned(M, JOB_SYNDICATE))
		temptext = span_italics("We have no need for you at this time. Have a pleasant day.") + "<br>"
		updateUsrDialog(user)
		return
	charges -= 1
	switch(rand(1,2))
		if(1)
			temptext = span_red(span_italics(span_bold("Double-crosser. You planned to betray us from the start. Allow us to repay the favor in kind.")))
			updateUsrDialog(user)
			after(src, rand(5 SECONDS,20 SECONDS), PROC_REF(selfdestruct))
			return
		if(2)
			return
	if(ishuman(M))
		var/mob/living/carbon/human/N = M
		to_chat(N, span_infoplain(span_bold("You have joined the ranks of the Syndicate and become a traitor to the station!")))
		GLOB.traitors.add_antagonist(N.mind)
		GLOB.traitors.equip(N)
		message_admins("[N]/([N.ckey]) has accepted a traitor objective from a syndicate beacon.")

	updateUsrDialog(user)

/obj/machinery/syndicate_beacon/proc/selfdestruct()
	selfdestructing = 1
	explosion(src.loc, 1, rand(1,3), rand(3,8), 10)

////////////////////////////////////////
//Singularity beacon
////////////////////////////////////////
/obj/machinery/power/singularity_beacon
	silicon_use = NONE // silicons can't use it
	name = "ominous beacon"
	desc = "This looks suspicious..."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "beacon"

	anchored = FALSE
	density = TRUE
	layer = MOB_LAYER - 0.1 //so people can't hide it and it's REALLY OBVIOUS

	active = 0
	var/icontype = "beacon"

/// Draws its (stealth) power while active.
/obj/machinery/power/singularity_beacon/proc/Activate(mob/user = null)
	if(surplus() < 1500)
		if(user)
			to_chat(user, span_notice("The connected wire doesn't have enough current."))
		return
	for(var/obj/singularity/singulo in REGISTRY_MEMBERS(REGISTRY_SINGULARITIES))
		if(singulo.z == z)
			singulo.target = src
	icon_state = "[icontype]1"
	set_active(1)
	if(user)
		to_chat(user, span_notice("You activate the beacon."))

/obj/machinery/power/singularity_beacon/proc/Deactivate(mob/user = null)
	for(var/obj/singularity/singulo in REGISTRY_MEMBERS(REGISTRY_SINGULARITIES))
		if(singulo.target == src)
			singulo.target = null
	icon_state = "[icontype]0"
	set_active(0)
	if(user)
		to_chat(user, span_notice("You deactivate the beacon."))

/obj/machinery/power/singularity_beacon/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(anchored)
		if(active)
			Deactivate(user)
		else
			Activate(user)
	else
		to_chat(user, span_danger("You need to screw the beacon to the floor first!"))
	return TRUE

/obj/machinery/power/singularity_beacon/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(active)
		to_chat(user, span_danger("You need to deactivate the beacon first!"))
		return OP_OK
	if(anchored)
		set_anchored(FALSE)
		to_chat(user, span_notice("You unscrew the beacon from the floor."))
		playsound(src, tool.usesound, 50, TRUE)
		disconnect_from_network()
		return OP_OK
	if(!connect_to_network())
		to_chat(user, "This device must be placed over an exposed cable.")
		return OP_OK
	set_anchored(TRUE)
	to_chat(user, span_notice("You screw the beacon to the floor and attach the cable."))
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK

// an active beacon deactivates.
/obj/machinery/power/singularity_beacon/on_destroy(force)
	if(active)
		Deactivate()
	..()

//stealth direct power usage
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/power/singularity_beacon)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(active), wakes_on = list(nameof(active)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("toggle", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Toggle"), then(PROC_REF(interaction_toggle)))

/obj/machinery/power/singularity_beacon/proc/work_step(datum/act/timer/A)
	if(draw_power(1500) < 1500)
		Deactivate()

/obj/machinery/power/singularity_beacon/syndicate
	icontype = "beaconsynd"
	icon_state = "beaconsynd0"

//  Virgo modified syndie beacon, does not give objectives

// attack_hand body relocated to code/modules/admin/misc_admin_panels.dm (structured TGUI).

/obj/machinery/syndicate_beacon/virgo/betraitor(mob/user, mob/M)
	if(charges < 1)
		updateUsrDialog(user)
		return
	if(!istype(M) || !M.mind)
		return
	if(M.mind.tcrystals > 0 || jobban_isbanned(M, JOB_SYNDICATE))
		temptext = "<i>We have no need for you at this time. Have a pleasant day.</i><br>"
		updateUsrDialog(user)
		return
	charges -= 1
	if(ishuman(M))
		var/mob/living/carbon/human/N = M
		to_chat(N, span_infoplain(span_bold("Access granted, here are the supplies!")))
		GLOB.traitors.spawn_uplink(N)
		N.mind.tcrystals = DEFAULT_TELECRYSTAL_AMOUNT
		N.mind.accept_tcrystals = 1
		message_admins("[N]/([N.ckey]) has received an uplink and telecrystals from the syndicate beacon.")

	updateUsrDialog(user)
