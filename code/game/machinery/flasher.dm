// It is a gizmo that flashes a small area
/obj/machinery/flasher
	name = "Mounted flash"
	desc = "A wall-mounted flashbulb device."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "mflash1"
	layer = ABOVE_WINDOW_LAYER
	flags = WALL_ITEM
	var/id = null
	var/range = 2 //this is roughly the size of brig cell
	var/disable = 0
	COOLDOWN_DECLARE(flash_cooldown) //Don't want it getting spammed like regular flashes
	var/strength = 10 //How weakened targets are when flashed.
	var/base_state = "mflash"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2

/obj/machinery/flasher/portable //Portable version of the flasher. Only flashes when anchored
	name = "portable flasher"
	desc = "A portable flashing device. Wrench to activate and deactivate. Cannot detect slow movements."
	icon_state = "pflash1"
	strength = 8
	anchored = FALSE
	base_state = "pflash"
	density = TRUE

CAPABILITIES(/obj/machinery/flasher/portable)
	after_init(0, then(PROC_REF(arm_proximity)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))

/// An anchored flasher senses proximity from the start.
/obj/machinery/flasher/portable/proc/arm_proximity(datum/act/timer/A)
	// Map start flashers enable proximity sensing
	if(anchored)
		add_overlay("[base_state]-s")
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/obj/machinery/flasher/power_change()
	. = ..()
	if(!power_lost())
		icon_state = "[base_state]1"
	else
		icon_state = "[base_state]1-p"

//Don't want to render prison breaks impossible
/obj/machinery/flasher/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	disable = !disable
	act_message(user, src, MSG_SELF(span_warning("You [disable ? "disconnect" : "connect"] %T%'s flashbulb!")), \
		MSG_OTHERS(span_warning("%U% has [disable ? "disconnected" : "connected"] %T%'s flashbulb!")))
	return OP_OK

//Let the AI trigger them directly.

/// Old attack_ai: the AI triggers it directly while it is anchored.
/obj/machinery/flasher/proc/flasher_silicon_trigger(datum/act/op/A)
	if(anchored)
		flash()
	return TRUE

/obj/machinery/flasher/proc/flash()
	if(!(powered()))
		return

	if((disable) || !COOLDOWN_FINISHED(src, flash_cooldown))
		return

	play_sfx(src, SFX_WEAPONS_FLASH)
	flick("[base_state]_flash", src)
	COOLDOWN_START(src, flash_cooldown, 15 SECONDS)
	use_power(1500)

	for (var/mob/O in viewers(src, null))
		if(get_dist(src, O) > range)
			continue

		var/flash_time = strength
		if(ishuman(O))
			var/mob/living/carbon/human/H = O
			if(H.nif && H.nif.flag_check(NIF_V_FLASHPROT,NIF_FLAGS_VISION))
				H.nif.notify("High intensity light detected, and blocked!",TRUE)
				continue
			if(H.has_mutation(FLASHPROOF))
				continue
			if(H.eyecheck() > 0)
				continue
			flash_time *= H.species.flash_mod
			var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
			if(!E)
				return
			if(E.is_bruised() && prob(E.damage + 50))
				H.flash_eyes()
				H.injure(INJURY_BURN, rand(1, 5), E, src, flags = INJURE_SILENT)
		else
			if(!O.blinded && isliving(O))
				var/mob/living/L = O
				L.flash_eyes()
		O.status_at_least(STAT_WEAKENED, flash_time)

CAPABILITIES(/obj/machinery/flasher)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(flasher_emp))))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wirecutter_used)))
	op("flasher_silicon_trigger", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Flash"), then(PROC_REF(flasher_silicon_trigger)))

/// An EMP may set the flasher off.
/obj/machinery/flasher/proc/flasher_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(!operable())
		return HOOK_DECLINE
	if(prob(75/packet.severity))
		flash()
	return HOOK_DECLINE

/obj/machinery/flasher/portable/HasProximity(turf/T, WF, oldloc)
	if(isnull(WF))
		return

	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	if(disable || !anchored || !COOLDOWN_FINISHED(src, flash_cooldown))
		return

	if(iscarbon(AM))
		var/mob/living/carbon/M = AM
		if(M.m_intent != I_WALK)
			flash()

/obj/machinery/flasher/portable/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	set_anchored(!anchored)
	if(!anchored)
		user.show_message(span_warning("[src] can now be moved."))
		cut_overlays()
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	else
		user.show_message(span_warning("[src] is now secured."))
		add_overlay("[base_state]-s")
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	return OP_OK

/obj/machinery/button/flasher
	name = "flasher button"
	desc = "A remote control switch for a mounted flasher."

CAPABILITIES(/obj/machinery/button/flasher)
	op("trigger", hand(), priority(OP_PRIORITY_DEFAULT), label("Press"), then(PROC_REF(interaction_trigger)))

/// Flashers sharing our id (keyed: linked when either end materializes).
/obj/machinery/button/flasher/var/list/obj/machinery/flasher/controlled_flashers
/obj/machinery/button/flasher/relations()
	. = ..()
	. += rel_many(nameof(controlled_flashers), keyed = nameof(id), keyed_target = /obj/machinery/flasher)
/obj/machinery/flasher/relations()
	. = ..()
	. += rel_key(nameof(id))

/obj/machinery/button/flasher/proc/interaction_trigger(datum/act/op/A)
	use_power(5)

	if(active)
		return TRUE

	set_active(TRUE)
	icon_state = "launcheract"

	for(var/obj/machinery/flasher/M as anything in controlled_flashers)
		M.flash()

	if(!after_pending(src, "finish_trigger"))
		after(src, 5 SECONDS, PROC_REF(finish_trigger), key = "finish_trigger")
	return TRUE

/obj/machinery/button/flasher/proc/finish_trigger()
	PRIVATE_PROC(TRUE)
	icon_state = "launcherbtt"
	set_active(FALSE)
