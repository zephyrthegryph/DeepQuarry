// AI Life: power, body, APU and vision as separate steps. The machine AI plan
// (plans/machine.dm) is the one death rule: hardware load, or an exhausted
// backup capacitor. The power-loss routine is a timer-driven state machine
// (aiRestorePowerRoutine = AI_POWER_*), not a sleeping spawn.

/mob/living/silicon/ai

/mob/living/silicon/ai
	life_set = LIFE_SET_AI

/// `if(stat == DEAD) return`, local failure cleanup and power.
/mob/living/silicon/ai/proc/life_ai_power(datum/seq_frame/life/F)
	if(src.stat == DEAD)
		return F.abort()

	if(src.stat != CONSCIOUS)
		rel_clear(src, nameof(src.cameraFollow))
		src.reset_perspective()
		src.disconnect_shell("Disconnecting from remote shell due to local system failure.")

	// If our powersupply object was destroyed somehow, create new one.
	if(!src.psupply)
		src.create_powersupply()

	src.process_ai_power()

/// Hardware integrity, capacitor and death are decided by the machine body.
/mob/living/silicon/ai/proc/life_ai_body(datum/seq_frame/life/F)
	src.body?.life_tick()
	if(src.stat == DEAD)
		return F.abort()

/// Lying down, malfunction, APU and queued alarms.
/mob/living/silicon/ai/proc/life_ai_upkeep(datum/seq_frame/life/F)
	src.lying = 0			// Handle lying down

	src.malf_process()
	src.process_apu()

	src.process_queued_alarms()

// --- Power ---------------------------------------------------------------------------------------

/// The backup capacitor drains while unpowered and recharges otherwise; losing
/// or regaining power drives the restore routine.
/mob/living/silicon/ai/proc/process_ai_power()
	var/unpowered = lacks_power()
	if(aiRestorePowerRoutine != AI_POWER_NORMAL && unpowered)
		adjust_backup_charge(-1)
	else
		adjust_backup_charge(1)

	if(unpowered)
		if(aiRestorePowerRoutine == AI_POWER_NORMAL)
			begin_power_loss()
		return

	switch(aiRestorePowerRoutine)
		if(AI_POWER_FAILED, AI_POWER_RESTORING)
			end_power_loss("Alert cancelled. Power has been restored without our assistance.")
		if(AI_POWER_RESTORED)
			end_power_loss("Alert cancelled. Power has been restored.")
		if(AI_POWER_NORMAL)
			// Something outside the routine (card, core transfer) reset the
			// state while the core was blind: restore sight once.
			if(!(sight & SEE_TURFS))
				cancel_power_restore()
				set_ai_vision(TRUE)
				update_icon()

/mob/living/silicon/ai/proc/lacks_power()
	if(APU_power)
		return 0
	var/turf/T = get_turf(src)
	var/area/A = get_area(src)
	return ((!A.power_equip) && A.requires_power == 1 || istype(T, /turf/space)) && !istype(src.loc,/obj/item)

/mob/living/silicon/ai/proc/adjust_backup_charge(amount)
	if(in_godmode(src))
		backup_charge = AI_BACKUP_CAPACITY
		return
	var/old_charge = backup_charge
	backup_charge = clamp(backup_charge + amount, 0, AI_BACKUP_CAPACITY)
	if(backup_charge != old_charge && (backup_charge <= 0 || old_charge <= 0))
		body?.on_status_changed()

/// Power just went out: blind the core and start the restore routine.
/mob/living/silicon/ai/proc/begin_power_loss()
	aiRestorePowerRoutine = AI_POWER_RESTORING
	update_icon()
	set_ai_vision(FALSE)
	to_chat(src, "You've lost power!")
	disconnect_shell(message = "Disconnected from remote shell due to depowered networking interface.")
	log_runtime("AI_POWER: [key_name(src)] lost power; restore routine started.")
	schedule_power_restore_step(1, 2 SECONDS)

/// Power is back: stop the routine and restore sight.
/mob/living/silicon/ai/proc/end_power_loss(message)
	cancel_power_restore()
	aiRestorePowerRoutine = AI_POWER_NORMAL
	if(message)
		to_chat(src, message)
	set_ai_vision(TRUE)
	update_icon()
	log_runtime("AI_POWER: [key_name(src)] power restored.")

/mob/living/silicon/ai/proc/schedule_power_restore_step(step, delay)
	cancel_power_restore()
	after(src, delay, PROC_REF(power_restore_step), key = "power_restore_timer", with = list(step))

/mob/living/silicon/ai/proc/cancel_power_restore()
	if(after_pending(src, "power_restore_timer"))
		cancel_after(src, "power_restore_timer")

/// One step of the restore routine. Each step reschedules the next.
/mob/living/silicon/ai/proc/power_restore_step(step)
	if(QDELETED(src) || stat == DEAD || aiRestorePowerRoutine != AI_POWER_RESTORING)
		return
	var/area/current_area = get_area(src)
	var/turf/T = get_turf(src)
	if(step > 1 && current_area?.power_equip && !istype(T, /turf/space))
		end_power_loss("Alert cancelled. Power has been restored without our assistance.")
		return
	switch(step)
		if(1)
			to_chat(src, "Backup battery online. Scanners, camera, and radio interface offline. Beginning fault-detection.")
			end_multicam()
			schedule_power_restore_step(2, AI_POWER_STEP)
		if(2)
			to_chat(src, "Fault confirmed: missing external power. Shutting down main control system to save power.")
			schedule_power_restore_step(3, 2 SECONDS)
		if(3)
			to_chat(src, "Emergency control system online. Verifying connection to power network.")
			schedule_power_restore_step(4, AI_POWER_STEP)
		if(4)
			if(istype(T, /turf/space))
				to_chat(src, "Unable to verify! No power connection detected!")
				aiRestorePowerRoutine = AI_POWER_FAILED
				return
			to_chat(src, "Connection verified. Searching for APC in power network.")
			schedule_power_restore_step(5, AI_POWER_STEP)
		if(5 to 8)
			var/attempt = step - 4
			var/obj/machinery/power/apc/theAPC = null
			for(var/obj/machinery/power/apc/APC in current_area)
				if(!APC.broken_now())
					theAPC = APC
					break
			if(!theAPC)
				to_chat(src, attempt == 1 ? "Unable to locate APC!" : "Lost connection with the APC!")
				aiRestorePowerRoutine = AI_POWER_FAILED
				return
			switch(attempt)
				if(1)
					to_chat(src, "APC located. Optimizing route to APC to avoid needless power waste.")
				if(2)
					to_chat(src, "Best route identified. Hacking offline APC power port.")
				if(3)
					to_chat(src, "Power port upload access confirmed. Loading control program into APC power port software.")
				if(4)
					to_chat(src, "Transfer complete. Forcing APC to execute program.")
			schedule_power_restore_step(step + 1, AI_POWER_STEP)
		if(9)
			var/obj/machinery/power/apc/theAPC = null
			for(var/obj/machinery/power/apc/APC in current_area)
				if(!APC.broken_now())
					theAPC = APC
					break
			if(!theAPC)
				to_chat(src, "Lost connection with the APC!")
				aiRestorePowerRoutine = AI_POWER_FAILED
				return
			to_chat(src, "Receiving control information from APC.")
			theAPC.set_equipment(3)
			theAPC.set_operating(1)
			aiRestorePowerRoutine = AI_POWER_RESTORED
			log_runtime("AI_POWER: [key_name(src)] forced [theAPC] on.")
			to_chat(src, "Here are your current laws:")
			show_laws()
			update_icon()

// --- APU -----------------------------------------------------------------------------------------

/mob/living/silicon/ai/proc/process_apu()
	if(APU_power && (hardware_integrity() < 50))
		to_chat(src, span_boldnotice("APU GENERATOR FAILURE! (System Damaged)"))
		stop_apu(1)

// --- Vision --------------------------------------------------------------------------------------

/// Sight follows power: set on the change, not every tick.
/mob/living/silicon/ai/proc/set_ai_vision(powered)
	if(powered)
		sight |= SEE_TURFS
		sight |= SEE_MOBS
		sight |= SEE_OBJS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_LIVING
		clear_fullscreen("blind")
		return
	overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
	sight &= ~SEE_TURFS
	sight &= ~SEE_MOBS
	sight &= ~SEE_OBJS
	see_in_dark = 0
	see_invisible = SEE_INVISIBLE_LIVING

/mob/living/silicon/ai/rejuvenate()
	// Restore the capacitor first: an empty one is lethal to the AI plan, and ..() revives.
	fully_heal()
	backup_charge = AI_BACKUP_CAPACITY
	..()
