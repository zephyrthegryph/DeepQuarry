
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
DECLARE_START_TIMER(/obj/machinery/bluespace_denier, 10 SECONDS, PROC_REF(start_up))

/obj/machinery/bluespace_denier/proc/start_up()
	if(anchored)
		add_overlay("[base_state]-s")
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/obj/machinery/bluespace_denier/power_change()
	. = ..()
	if(!has_stat(NOPOWER))
		icon_state = "[base_state]1"
	else
		icon_state = "[base_state]1-p"

//Let the AI trigger them directly.
EXTEND_INTERACTIONS(/obj/machinery/bluespace_denier, INTERACT_SILICON("Pulse", PROC_REF(bluespace_denier_silicon_trigger)))

/// Old attack_ai: the AI triggers it directly while it is anchored.
/obj/machinery/bluespace_denier/proc/bluespace_denier_silicon_trigger(mob/user, obj/item/held, datum/interaction/interaction)
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

/obj/machinery/bluespace_denier/emp_act(severity)
	if(!operable())
		..(severity)
		return
	if(prob(75/severity))
		pulse()
	..(severity)

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

/obj/machinery/bluespace_denier/wrench_act(mob/user, obj/item/tool)
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
	return ITEM_INTERACT_SUCCESS
