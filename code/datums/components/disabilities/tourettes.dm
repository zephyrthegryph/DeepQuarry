/datum/component/tourettes_disability
	var/mob/living/owner
	var/list/motor_tics

/datum/component/tourettes_disability/Initialize()
	if (!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

	owner = parent
	var/list/possible_tics = list(
		"nod",
		"shake",
		"shiver",
		"twitch",
		"salute",
		"blink",
		"blink_r",
		"wink",
		"shrug",
		"eyebrow",
		"afold",
		"hshrug",
		"ftap",
		"sniff",
		"cough",
		"snap",
		"whistle",
		"qwhistle",
		"wwhistle",
		"swhistle",
		"awoo",
		"prbt",
		"snort",
		"merp",
		"nya",
		"crack",
		"rshoulder"
	)
	for(var/i = 0, i < rand(4, 6), i++)
		LAZYADD(motor_tics, pick(possible_tics))
	RegisterSignal(owner, COMSIG_HANDLE_DISABILITIES, PROC_REF(process_component))

/datum/component/tourettes_disability/proc/process_component()
	SIGNAL_HANDLER

	var/mob/living/carbon/human/H = owner

	if(QDELETED(parent))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if(owner.client && (owner.client.prefs.muted & MUTE_IC))
		return
	if(owner.status_units(EFFECT_PARALYZED) <= 1 && (H.pulse <= PULSE_NORM ? (prob(1)) : (prob(50))))
		owner.status_adjust(EFFECT_JITTERY, 30 + rand(10, 30))
		owner.emote(DEFAULTPICK(motor_tics, null))

/datum/component/tourettes_disability/Destroy(force = FALSE)
	UnregisterSignal(owner, COMSIG_HANDLE_DISABILITIES)
	owner = null
	. = ..()
