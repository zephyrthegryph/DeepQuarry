/mob/thing
	var/pulses = 0

OM_FIELD(/mob/thing, pulsing, FALSE, CHANGE_EXPLICIT)
DECLARE_REPEAT(/mob/thing, 0.5 SECONDS, pulse, "pulsing")

/mob/thing/proc/pulse()
	pulses++
