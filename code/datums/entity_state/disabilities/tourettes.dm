/// Was /datum/component/tourettes_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(tourettes_disability, CAP_DISABILITY_TOURETTES, /datum/capability/disability/tourettes, key = NONE)
/datum/capability/disability/tourettes
	required_type = /mob/living/carbon/human

/mob/living/carbon/human
	/// Tourettes disability: this mob's motor tics, picked when the disability starts.
	var/list/disability_motor_tics

/datum/capability/disability/tourettes/proc/pick_tics(mob/living/carbon/human/owner)
	if(!istype(owner) || LAZYLEN(owner.disability_motor_tics))
		return
	var/static/list/possible_tics = list(
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
		LAZYADD(owner.disability_motor_tics, pick(possible_tics))

/datum/capability/disability/tourettes/disability_tick(mob/living/carbon/human/owner)
	if(!LAZYLEN(owner.disability_motor_tics))
		pick_tics(owner)

	var/mob/living/carbon/human/H = owner

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if(owner.client && (owner.client.prefs.muted & MUTE_IC))
		return
	if(owner.status_units(STAT_PARALYZED) <= 1 && (H.pulse <= PULSE_NORM ? (prob(1)) : (prob(50))))
		owner.status_adjust(STAT_JITTERY, 30 + rand(10, 30))
		owner.emote(DEFAULTPICK(owner.disability_motor_tics, null))
