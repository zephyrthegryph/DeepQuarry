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

	var/beep = TRUE

/// The patient on the monitor (a relation view), or null.
OM_FIELD_VIEW(/obj/machinery/vitals_monitor, mob/living/carbon/human, victim, CHANGE_MACHINE_OCCUPANT)
/// Tracks its patient while connected to someone.

/obj/machinery/vitals_monitor/examine(mob/user)
	. = ..()
	if(victim())
		if(has_stat(NOPOWER))
			. += span_notice("It's unpowered.")
			return
		. += span_notice("Vitals of [victim()]:")
		var/datum/diagnosis/D = victim().diagnose(/datum/diagnostic_profile/vitals_monitor)
		var/vitals_text = D?.render_vitals_text()
		spent(D, user)
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

/// Tracks its patient while it has one (the declaration above).
/obj/machinery/vitals_monitor/proc/work_step(datum/act/timer/A)
	if(!victim() || QDELETED(victim()))
		rel_clear(src, nameof(victim))
		set_use_power(USE_POWER_IDLE)
	if(victim() && !Adjacent(victim()))
		rel_clear(src, nameof(victim))
		set_use_power(USE_POWER_IDLE)
	if(victim())
		update_icon()
	if(beep && victim() && victim().pulse)
		play_sfx(src, SFX_MACHINES_QUIET_BEEP, volume = 0)

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/machinery/vitals_monitor/proc/drop_input(datum/act/input/A)
	drop_patient_with_actor(A.actor, A.over)
	return TRUE

/obj/machinery/vitals_monitor/proc/drop_patient_with_actor(mob/user, atom/over_object)
	if(!CanMouseDrop(over_object, user))
		return
	if(victim())
		rel_clear(src, nameof(victim))
		set_use_power(USE_POWER_IDLE)
	else if(ishuman(over_object))
		rel_set(src, nameof(victim), over_object)
		set_use_power(USE_POWER_ACTIVE)
		visible_message(span_notice("\The [src] is now showing data for [victim()]."))

/obj/machinery/vitals_monitor/draw(datum/look/look)
	..()
	if(has_stat(NOPOWER))
		return
	look.overlay("screen")

	if(!victim())
		return

	switch(victim().pulse)
		if(PULSE_NONE)
			look.overlay("pulse_flatline")
			look.overlay("pulse_warning")
		if(PULSE_SLOW, PULSE_NORM,)
			look.overlay("pulse_normal")
		if(PULSE_FAST, PULSE_2FAST)
			look.overlay("pulse_veryfast")
		if(PULSE_THREADY)
			look.overlay("pulse_thready")
			look.overlay("pulse_warning")

	var/obj/item/organ/internal/brain/brain = victim().organ_in(O_BRAIN)
	if(istype(brain) && victim().stat != DEAD && !(victim().status_flags & FAKEDEATH))
		if(victim().injury_load(INJURY_CATEGORY_NEURAL))
			look.overlay("brain_verybad")
			look.overlay("brain_warning")
		else if(victim().stat == UNCONSCIOUS)
			look.overlay("brain_bad")
		else
			look.overlay("brain_ok")
	else
		look.overlay("brain_warning")

	var/obj/item/organ/internal/lungs/lungs = victim().organ_in(O_LUNGS)
	if(istype(lungs) && victim().stat != DEAD && !(victim().status_flags & FAKEDEATH))
		switch(breathing_band())
			if("erratic")
				look.overlay("breathing_shallow")
				look.overlay("breathing_warning")
			if("shallow")
				look.overlay("breathing_shallow")
			else
				look.overlay("breathing_normal")
	else
		look.overlay("breathing_warning")

/// Breathing quality from the patient's oxygen saturation.
/obj/machinery/vitals_monitor/proc/breathing_band()
	var/saturation = victim().body?.oxygenation()
	if(isnull(saturation) || saturation >= 93)
		return "normal"
	if(saturation >= 85)
		return "shallow"
	return "erratic"

CAPABILITIES(/obj/machinery/vitals_monitor)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(victim), wakes_on = list(nameof(victim)))
	op("vitals_monitor_toggle_beep", menu(), label("Toggle Monitor Beeping"), then(PROC_REF(vitals_monitor_toggle_beep)))
	drag_onto(PROC_REF(drop_input))
	default_parts()

/// Old verb "Toggle Monitor Beeping".
/obj/machinery/vitals_monitor/proc/vitals_monitor_toggle_beep(datum/act/op/A)
	var/mob/user = A.actor
	if(!istype(user))
		return

	if(CanInteract(user, GLOB.tgui_physical_state))
		beep = !beep
		to_chat(user, span_notice("You turn the sound on \the [src] [beep ? "on" : "off"]."))

/// victim (a relation view: it reads null once the target is deleted).
/obj/machinery/vitals_monitor/proc/victim() as /mob/living/carbon/human
	return victim
