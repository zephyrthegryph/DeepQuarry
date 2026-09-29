/obj/item/circuitboard/machine/vitals_monitor
	name = T_BOARD("vitals monitor")
	build_path = /obj/machinery/vitals_monitor
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stock_parts/console_screen = 1,
		/obj/item/cell/high = 1
	)

/obj/machinery/vitals_monitor
	name = "vitals monitor"
	desc = "A bulky yet mobile machine, showing some odd graphs."
	icon = 'icons/obj/heartmonitor.dmi'
	icon_state = "base"
	anchored = FALSE
	power_channel = EQUIP
	idle_power_usage = 10
	active_power_usage = 100

	var/mob/living/carbon/human/victim
	var/beep = TRUE

/obj/machinery/vitals_monitor/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/vitals_monitor/examine(mob/user)
	. = ..()
	if(victim())
		if(stat & NOPOWER)
			. += span_notice("It's unpowered.")
			return
		. += span_notice("Vitals of [victim()]:")
		var/datum/diagnosis/D = victim().diagnose(/datum/diagnostic_profile/vitals_monitor)
		var/vitals_text = D?.render_vitals_text()
		qdel(D)
		if(vitals_text)
			. += span_notice(vitals_text)

		var/brain_activity = "none"
		var/breathing = "none"

		if(victim().stat != DEAD && !(victim().status_flags & FAKEDEATH))
			var/obj/item/organ/internal/brain/brain = victim().organ_in(O_BRAIN)
			if(istype(brain))
				if(victim().injury_load(INJURY_CATEGORY_NEURAL) || is_changeling(victim()) || has_trait(victim(), UNIQUE_MINDSTRUCTURE))
					brain_activity = "anomalous"
				else if(victim().stat == UNCONSCIOUS)
					brain_activity = "weak"
				else
					brain_activity = "normal"

			var/obj/item/organ/internal/lungs/lungs = victim().organ_in(O_LUNGS)
			if(istype(lungs))
				if(victim().breath_blocked())
					breathing = "none"
				else
					breathing = breathing_band()

		. += span_notice("Brain activity: [brain_activity]")
		. += span_notice("Breathing: [breathing]")

/// Tracks its patient while it has one; otherwise it sleeps until connected to someone.
/obj/machinery/vitals_monitor/machine_step()
	if(!victim())
		return PROCESS_KILL
	if(QDELETED(victim()))
		rel_clear(src, "victim")
		update_icon()
		update_use_power(USE_POWER_IDLE)
	if(victim() && !Adjacent(victim()))
		rel_clear(src, "victim")
		update_icon()
		update_use_power(USE_POWER_IDLE)
	if(victim())
		update_icon()
	if(beep && victim() && victim().pulse)
		playsound(src, 'sound/machines/quiet_beep.ogg')

/obj/machinery/vitals_monitor/MouseDrop(over_object, src_location, over_location)
	if(!CanMouseDrop(over_object))
		return
	if(victim())
		rel_clear(src, "victim")
		update_use_power(USE_POWER_IDLE)
	else if(ishuman(over_object))
		rel_set(src, "victim", over_object)
		update_use_power(USE_POWER_ACTIVE)
		MACHINE_WAKE(src)
		visible_message(span_notice("\The [src] is now showing data for [victim()]."))

/obj/machinery/vitals_monitor/update_icon()
	cut_overlays()
	if(stat & NOPOWER)
		return
	add_overlay("screen")

	if(!victim())
		return

	switch(victim().pulse)
		if(PULSE_NONE)
			add_overlay("pulse_flatline")
			add_overlay("pulse_warning")
		if(PULSE_SLOW, PULSE_NORM,)
			add_overlay("pulse_normal")
		if(PULSE_FAST, PULSE_2FAST)
			add_overlay("pulse_veryfast")
		if(PULSE_THREADY)
			add_overlay("pulse_thready")
			add_overlay("pulse_warning")

	var/obj/item/organ/internal/brain/brain = victim().organ_in(O_BRAIN)
	if(istype(brain) && victim().stat != DEAD && !(victim().status_flags & FAKEDEATH))
		if(victim().injury_load(INJURY_CATEGORY_NEURAL))
			add_overlay("brain_verybad")
			add_overlay("brain_warning")
		else if(victim().stat == UNCONSCIOUS)
			add_overlay("brain_bad")
		else
			add_overlay("brain_ok")
	else
		add_overlay("brain_warning")

	var/obj/item/organ/internal/lungs/lungs = victim().organ_in(O_LUNGS)
	if(istype(lungs) && victim().stat != DEAD && !(victim().status_flags & FAKEDEATH))
		switch(breathing_band())
			if("erratic")
				add_overlay("breathing_shallow")
				add_overlay("breathing_warning")
			if("shallow")
				add_overlay("breathing_shallow")
			else
				add_overlay("breathing_normal")
	else
		add_overlay("breathing_warning")

/// Breathing quality from the patient's oxygen saturation.
/obj/machinery/vitals_monitor/proc/breathing_band()
	var/saturation = victim().body?.oxygenation()
	if(isnull(saturation) || saturation >= 93)
		return "normal"
	if(saturation >= 85)
		return "shallow"
	return "erratic"

EXTEND_INTERACTIONS(/obj/machinery/vitals_monitor, \
	INTERACT_VERB("Toggle Monitor Beeping", PROC_REF(vitals_monitor_toggle_beep)), \
)

/// Old verb "Toggle Monitor Beeping".
/obj/machinery/vitals_monitor/proc/vitals_monitor_toggle_beep(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user))
		return

	if(CanInteract(user, GLOB.tgui_physical_state))
		beep = !beep
		to_chat(user, span_notice("You turn the sound on \the [src] [beep ? "on" : "off"]."))

/// LC-refs: victim -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/vitals_monitor/proc/victim() as /mob/living/carbon/human
	return victim
