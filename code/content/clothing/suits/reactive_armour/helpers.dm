/// after() target: the misfired cloak wears off.
/proc/reactive_cloak_wear_off(mob/living/attacker, old_alpha)
	attacker.set_alpha(old_alpha)
