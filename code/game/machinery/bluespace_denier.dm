
/obj/machinery/bluespace_denier
	name = "bluespace desyncronizer"
	desc = "A portable device that causes small disruptions to bluespace when its sensors detect activity within it nearby. Wrench to activate and deactivate."
	icon = 'icons/obj/machines/bs_disruptor.dmi'
	icon_state = "pflash1"
	layer = ABOVE_WINDOW_LAYER
	var/range = 4
	COOLDOWN_DECLARE(pulse_cooldown) //Don't want it getting spammed like regular flashes
	var/base_state = "mflash"
	anchored = FALSE
	base_state = "pflash"
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2

// if already anchored, setup the proximity check

/obj/machinery/bluespace_denier/proc/start_up(datum/act/A)
	if(anchored)
		add_overlay("[base_state]-s")
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/obj/machinery/bluespace_denier/power_change()
	. = ..()
	if(!power_lost())
		icon_state = "[base_state]1"
	else
		icon_state = "[base_state]1-p"

//Let the AI trigger them directly.

/// Old attack_ai: the AI triggers it directly while it is anchored.
/obj/machinery/bluespace_denier/proc/bluespace_denier_silicon_trigger(datum/act/op/A)
	if(anchored)
		pulse()
	return TRUE

/obj/machinery/bluespace_denier/proc/pulse()
	if(!(powered()))
		return

	if(!COOLDOWN_FINISHED(src, pulse_cooldown))
		return

	play_sfx(src, SFX_WEAPONS_FLASH)
	flick("[base_state]_flash", src)
	COOLDOWN_START(src, pulse_cooldown, 15 SECONDS)
	use_power(1500)

	for(var/mob/living/O in range(range, src))
		var/datum/shadekin/SK = O.get_shadekin_state()
		if(!SK)
			continue
		SK.attack_dephase(null, src) //Won't dephase them if they're not in phase. It has built in checks.

CAPABILITIES(/obj/machinery/bluespace_denier)
	after_init(10 SECONDS, then(PROC_REF(start_up)))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(denier_emp))))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("bluespace_denier_silicon_trigger", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Pulse"), then(PROC_REF(bluespace_denier_silicon_trigger)))

/// An EMP may set off a pulse.
/obj/machinery/bluespace_denier/proc/denier_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(!operable())
		return HOOK_DECLINE
	if(prob(75/packet.severity))
		pulse()
	return HOOK_DECLINE

/obj/machinery/bluespace_denier/HasProximity(turf/T, WF, oldloc)
	if(isnull(WF))
		return

	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return

	if(!anchored || !COOLDOWN_FINISHED(src, pulse_cooldown))
		return

	if(ishuman(AM))
		pulse()

/obj/machinery/bluespace_denier/proc/wrench_used(datum/act/op/A)
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
