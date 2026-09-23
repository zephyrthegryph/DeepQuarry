/mob/living/silicon/ai/examine(mob/user)
	. = ..()

	if (src.stat == DEAD)
		. += span_deadsay("It appears to be powered-down.")
	else
		. += machine_examine_lines(src)
		var/backup_drain = AI_BACKUP_CAPACITY - backup_charge
		if (backup_drain && (aiRestorePowerRoutine != 0 && !APU_power))
			if (backup_drain > 175)
				. += span_boldwarning("It seems to be running on backup power. Its display is blinking a \"BACKUP POWER CRITICAL\" warning.")
			else if(backup_drain > 100)
				. += span_boldwarning("It seems to be running on backup power. Its display is blinking a \"BACKUP POWER LOW\" warning.")
			else
				. += span_warning("It seems to be running on backup power.")

		if (src.stat == UNCONSCIOUS)
			. += span_warning("It is non-responsive and displaying the text: \"RUNTIME: Sensory Overload, stack 26/3\".")

		if(deployed_shell)
			. += "The wireless networking light is blinking."

	. += ""

	if(hardware && (hardware.owner == src))
		. += hardware.get_examine_desc()

	user.showLaws(src)

/mob/proc/showLaws(mob/living/silicon/S)
	return

/mob/observer/dead/showLaws(mob/living/silicon/S)
	if(antagHUD || is_admin(src))
		S.laws.show_laws(src)
