/obj/item/rig_module/pat_module
	name = "\improper P.A.T. module"
	desc = "A \'Pre-emptive Access Tunneling\' module, for opening every door in a hurry."
	icon_state = "cloak"

	var/range = 3

	usable = 1
	toggleable = 1
	disruptable = 1
	disruptive = 0

	use_power_cost = 100
	active_power_cost = 1
	passive_power_cost = 0
	module_cooldown = 30

	activate_string = "Enable P.A.T."
	deactivate_string = "Disable P.A.T."
	engage_string = "Override Airlock"

	interface_name = "PAT system"
	interface_desc = "For opening doors ahead of you, in advance. Override notifies command staff."

CAPABILITIES(/obj/item/rig_module/pat_module)
	// The wearer's override of the airlock they face: six seconds, and walking off ends it. engage() starts it with the airlock as "door".
	op("override", ai(), takes("door"), begins(MSG(pat_module/overriding)), wait(6 SECONDS), then(PROC_REF(override_done)))

MSG_DEF(pat_module/overriding, span_notice("You begin overriding the airlock!"), span_warning("%U% begins overriding the airlock!"))

/obj/item/rig_module/pat_module/activate(skip_engage = 0, mob/user)
	if(!..(TRUE, user)) //Skip the engage() call, that's for the override and is 'spensive.
		return 0

	var/mob/living/carbon/human/H = holder.wearer()
	to_chat(H,span_notice("You activate the P.A.T. module."))
	dq_add_recursive_move(H)
	observe(H, /datum/notice/movable_attempted_move, src, then(PROC_REF(boop)))

/obj/item/rig_module/pat_module/deactivate(forced = FALSE, mob/user)
	if(!..())
		return 0

	var/mob/living/carbon/human/H = holder.wearer()
	to_chat(H,span_notice("Your disable the P.A.T. module."))
	unobserve(H, /datum/notice/movable_attempted_move, src)

/obj/item/rig_module/pat_module/proc/boop(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = N.target
	var/datum/notice/movable_attempted_move/event = N
	var/mob/living/carbon/human/user = source
	var/turf/To = event.old_loc
	var/turf/Tn = event.new_loc
	if(!istype(user) || !istype(To) || !istype(Tn))
		deactivate() //They were picked up or something, or put themselves in a locker, who knows. Just turn off.
		return

	var/direction = user.dir
	var/turf/current = Tn
	for(var/i = 0; i < range; i++)
		current = get_step(current,direction)
		if(!current) break

		var/obj/machinery/door/airlock/A = locate_on(current, /obj/machinery/door/airlock)
		if(!A || !A.density) continue

		if(A.allowed(user) && A.operable())
			A.open()

/obj/item/rig_module/pat_module/proc/override_done(datum/act/op/A)
	var/obj/machinery/door/airlock/door = A.arg("door")
	if(!QDELETED(door) && door.density)
		door.open()
	return OP_OK

/obj/item/rig_module/pat_module/engage(atom/target, notify_ai, mob/user)
	var/mob/living/carbon/human/H = holder.wearer()
	if(!istype(H))
		return 0

	var/obj/machinery/door/airlock/A = locate_in_list(get_step(H,H.dir), /obj/machinery/door/airlock)

	//Okay, we either found an airlock or we're about to give up.
	if(!A || !A.density || !A.can_open() || !..())
		to_chat(H,span_warning("Unable to comply! Energy too low, or not facing a working airlock!"))
		return 0

	perform_op(H, src, "override", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("door" = A))

	var/username = FindNameFromID(H) || "Unknown"
	var/message = "[username] has overridden [A] (airlock) in \the [get_area(A)] at [A.x],[A.y],[A.z] with \the [src]."
	GLOB.global_announcer.autosay(message, "Security Subsystem", "Command")
	GLOB.global_announcer.autosay(message, "Security Subsystem", "Security")
	return 1
