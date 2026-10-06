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

/// Re-checked on the answer: still carried, and not already active.
/datum/prompt/yes_no/emergency_beacon
	question = "Would you like to activate this personal emergency beacon?"
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	timeout = 0

/datum/prompt/yes_no/emergency_beacon/recheck_extra()
	var/obj/item/emergency_beacon/B = owner
	return B.beacon_active ? "already active" : null

/obj/item/emergency_beacon/proc/activation_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/user = A.request.answerer
	//short delay, so they can still abort if they want to
	task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(activate_done), done_args = list(user))

DECLARE_INTERACTIONS(/obj/item/emergency_beacon, \
	INTERACT_USE("Activate", PROC_REF(interaction_self)), \
	INTERACT_HAND(null, PROC_REF(interaction_hand), REQ_BECAUSE(REQ_FIELD_NOT("beacon_active"), "it's already active and cannot be moved")), \
	INTERACT_ITEM("Disassemble", PROC_REF(interaction_item)), \
)

/obj/item/emergency_beacon/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/T = user.loc
	if(!beacon_active)
		if(!isturf(T))
			to_chat(user,span_warning("You cannot activate the beacon when you are not on a turf!"))
			return
		else if(isnonsolidturf(T))
			to_chat(user,span_warning("You cannot activate the beacon when you are not on sufficiently solid ground!"))
			return
		else
			open_request(src, /datum/prompt/yes_no/emergency_beacon, PROC_REF(activation_answered), answerer = user, title = "\The [src]")
	else
		to_chat(user,"\The [src] is already active, or is otherwise malfunctioning. There's nothing you can do but wait. And possibly pray.")
	return TRUE

/obj/item/emergency_beacon/proc/activate_done(mob/user)
	if(beacon_active)
		return
	act_message(user, src, MSG_SELF(span_warning("You activate %T%, spiking it into the ground!")), MSG_OTHERS(span_warning("%U% activates %T%!")))
	beacon_active = TRUE
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
/obj/item/emergency_beacon/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	return FALSE

/// Old attackby: wrench it apart once active.
/obj/item/emergency_beacon/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(W.has_tool_quality(TOOL_WRENCH) && beacon_active)
		gps.set_tracking(FALSE)
		act_message(user, src, others = "%U% disassembles %T%.")
		consume(src, user)
		return TRUE
	return FALSE

/obj/item/emergency_beacon/ownership()
	. = ..()
	. += owns(nameof(gps), policy = OWN_CONTAINED, starts = /obj/item/gps/emergency_beacon)
