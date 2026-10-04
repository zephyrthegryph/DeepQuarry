/mob/thing
	var/pulses = 0

/mob/thing/var/pulsing = FALSE
TRACKED(/mob/thing, pulsing)
CAPABILITIES(/mob/thing)
	every(0.5 SECONDS, then(PROC_REF(pulse)), when = nameof(pulsing))

/mob/thing/proc/pulse(datum/act/timer/A)
	pulses++
