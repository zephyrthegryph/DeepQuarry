/obj/item/emergency_beacon
	name = "personal emergency beacon"
	desc = "The hardy PersonaL Emergency Beacon, or PLEB, is a simple device that, once activated, sends out a wideband distress signal that can punch through almost all forms of interference. They are commonly issued to miners and remote exploration teams who may find themselves in need of means to call for assistance whilst being out of conventional communications range."
	icon = 'icons/obj/device.dmi'
	icon_state = "e_beacon_off"
	var/beacon_active = FALSE
	var/list/levels_for_distress
	var/obj/item/gps/gps = null
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/item/emergency_beacon/Initialize(mapload)
	for(var/i in 1 to length(levels_for_distress))
		var/current = levels_for_distress[i]
		if(isnum(current))
			continue
		levels_for_distress[i] = GLOB.map_templates_loaded[current]
	if(!levels_for_distress)
		levels_for_distress = list(1)
	return ..()

/obj/item/gps/emergency_beacon
	gps_tag = "EMERGENCY BEACON"

TRACKED(/obj/item/emergency_beacon, beacon_active)

CAPABILITIES(/obj/item/emergency_beacon)
	owns_one(nameof(gps), /obj/item/gps, starts = /obj/item/gps/emergency_beacon)
	// the old attack_self: on solid ground, after a yes, the beacon is spiked in a moment later
	op("activate", in_hand(), label("Activate"), needs(req_is(nameof(beacon_active), FALSE, because = MSG(emergency_beacon/active)), req(PROC_REF(on_solid_ground), because = PROC_REF(ground_refusal))),
		asks(/datum/prompt/yes_no, fields = list("title" = "name", "question" = "Would you like to activate this personal emergency beacon?", "timeout" = 0), ends_on_no = TRUE),
		wait(3 SECONDS), // short, so they can still abort if they want to
		then(PROC_REF(activate_done)))
	// an active beacon is spiked in: it can't be picked up, and a wrench takes it apart
	op("spiked", hand(), when(nameof(beacon_active)), then(PROC_REF(interaction_hand)))
	op("disassemble", tool(TOOL_WRENCH), wait(0), label("Disassemble"), when(nameof(beacon_active)), then(PROC_REF(interaction_item)))

MSG_DEF_SELF(emergency_beacon/active, "It is already active, or is otherwise malfunctioning. There's nothing you can do but wait. And possibly pray.")

/// Requirement: the actor stands on solid ground.
/obj/item/emergency_beacon/proc/on_solid_ground(datum/act/op/A)
	return isnull(ground_refusal(A))

/obj/item/emergency_beacon/proc/ground_refusal(datum/act/op/A)
	return beacon_ground_refusal(A.actor)

/proc/beacon_ground_refusal(mob/user)
	READS_FROM() // where the actor stands is asked when the beacon is activated
	var/T = user.loc
	if(!isturf(T))
		return "You cannot activate the beacon when you are not on a turf!"
	if(isnonsolidturf(T))
		return "You cannot activate the beacon when you are not on sufficiently solid ground!"
	return null

/obj/item/emergency_beacon/proc/activate_done(datum/act/op/A)
	var/mob/user = A.actor
	if(beacon_active)
		return
	act_message(user, src, MSG_SELF(span_warning("You activate %T%, spiking it into the ground!")), MSG_OTHERS(span_warning("%U% activates %T%!")))
	set_beacon_active(TRUE)
	icon_state = "e_beacon_active"
	user.drop_item()
	set_anchored(TRUE)
	gps.set_tracking(TRUE)
	admin_chat_message(message = "'[user?.ckey || "Unknown"]' activated a personal emergency beacon", color = "#FF2222")
	var/message = "This is an automated distress signal from a MIL-DTL-93352-compliant personal emergency beacon transmitting on [PUB_FREQ*0.1]kHz. \
	This beacon was activated in '\the [get_area(src)]' at X[src.loc.x], Y[src.loc.y]. Due to the limited signal strength, no further information can be provided at this time. \
	Per the Interplanetary Convention on Space SAR, those receiving this message must attempt rescue, \
	or relay the message to those who can."

	for(var/zlevel in levels_for_distress)
		GLOB.priority_announcement.Announce(message, new_title = "Automated Personal Distress Signal", new_sound = ANNOUNCER_MSG_DISTRESS_SIGNAL, zlevel = zlevel)

/// Old attack_hand: block pickup while the beacon is active (the requirement refuses it); otherwise fall through to pickup.
/obj/item/emergency_beacon/proc/interaction_hand(datum/act/op/A)
	to_chat(A.actor, span_warning("It's already active and cannot be moved."))
	return OP_OK

/// Old attackby: wrench it apart once active.
/obj/item/emergency_beacon/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	gps.set_tracking(FALSE)
	act_message(user, src, others = "%U% disassembles %T%.")
	consume(src, user)
	return OP_OK


