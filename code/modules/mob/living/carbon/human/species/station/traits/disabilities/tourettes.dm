/// Was /datum/component/tourettes_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(tourettes_disability, CAP_DISABILITY_TOURETTES, /datum/capability/disability/tourettes, key = NONE)
/datum/capability/disability/tourettes
	required_type = /mob/living/carbon/human

/mob/living/carbon/human
	/// Tourettes disability: this mob's motor tics, picked when the disability starts.

/datum/capability/disability/tourettes/proc/pick_tics(mob/living/carbon/human/owner)
	if(!istype(owner) || LAZYLEN(sparse_get(owner, disability_motor_tics)))
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
	var/list/tics = sparse_get(owner, disability_motor_tics)
	for(var/i = 0, i < rand(4, 6), i++)
		LAZYADD(tics, pick(possible_tics))
	sparse_set(owner, disability_motor_tics, tics)

/datum/capability/disability/tourettes/disability_tick(mob/living/carbon/human/owner)
	if(!LAZYLEN(sparse_get(owner, disability_motor_tics)))
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
		owner.emote(DEFAULTPICK(sparse_get(owner, disability_motor_tics), null))

sparse(/mob/living/carbon/human, disability_motor_tics, type = list)
