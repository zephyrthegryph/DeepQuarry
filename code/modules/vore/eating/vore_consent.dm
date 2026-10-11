// Existing profile fields publish on their actual record and owning mob. No base vars added.
TRACKED_DATA(/datum/record/vore_prefs, devourable)
TRACKED_DATA(/datum/record/vore_prefs, digestable)
TRACKED_DATA(/datum/record/vore_prefs, absorbable)
TRACKED_DATA(/datum/record/vore_prefs, permit_healbelly)
TRACKED_DATA(/datum/record/vore_prefs, strip_pref)
TRACKED_DATA(/datum/record/vore_prefs, contaminate_pref)

// Native consent requirements, actor=predator, target=prey.
/datum/entry/part/req/vore_consent/check(datum/act/op/A)
	return consent_reason(A)

/datum/entry/part/req/vore_consent/proc/consent_reason(datum/act/op/A)
	return /datum/msg/req_failed

/datum/entry/part/req/vore_consent/devourable/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	if(!prey || !prey.vore_prefs.devourable)
		return "They aren't able to be devoured."
	return null

/datum/entry/part/req/vore_consent/devourable/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "devourable"))

/datum/entry/part/req/vore_consent/devour/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	var/mob/living/pred = istype(A.actor, /mob/living) ? A.actor : null
	if(!prey || !prey.vore_prefs.devourable)
		return "They aren't able to be devoured."
	if(!prey || prey.absorbed)
		return "They aren't in a state to be devoured."
	if(!pred || pred.absorbed)
		return "They aren't in a state to be devoured."
	return null

/datum/entry/part/req/vore_consent/devour/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "devourable"))
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "absorbed"))
	if(istype(A.actor, /mob/living))
		. += list(list(A.actor, "absorbed"))

/datum/entry/part/req/vore_consent/digest/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	if(!prey || !prey.vore_prefs.digestable)
		return "they don't allow digestion"
	if(!prey || prey.absorbed)
		return "they are already absorbed"
	return null

/datum/entry/part/req/vore_consent/digest/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "digestable"))
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "absorbed"))

/datum/entry/part/req/vore_consent/absorb/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	if(!prey || !prey.vore_prefs.absorbable)
		return "they don't allow absorption"
	if(!prey || prey.absorbed)
		return "they are already absorbed"
	return null

/datum/entry/part/req/vore_consent/absorb/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "absorbable"))
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "absorbed"))

/datum/entry/part/req/vore_consent/heal/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	if(!prey || !prey.vore_prefs.permit_healbelly)
		return "they don't allow healing bellies"
	if(!prey || prey.is_dead())
		return "they are dead"
	return null

/datum/entry/part/req/vore_consent/heal/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "permit_healbelly"))
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "stat"))

/datum/entry/part/req/vore_consent/strip/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	if(!prey || !prey.vore_prefs.strip_pref)
		return "they don't allow stripping"
	return null

/datum/entry/part/req/vore_consent/strip/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "strip_pref"))

/datum/entry/part/req/vore_consent/affect_worn/consent_reason(datum/act/op/A)
	var/mob/living/prey = istype(A.target, /mob/living) ? A.target : null
	if(!prey || !prey.vore_prefs.contaminate_pref)
		return "they don't allow their worn items to be affected"
	return null

/datum/entry/part/req/vore_consent/affect_worn/read_keys(datum/act/op/A)
	. = list()
	if(istype(A.target, /mob/living))
		. += list(list(A.target, "vore_prefs"), list(A.target.vars["vore_prefs"], "contaminate_pref"))

/// A real native requirement evaluation; pooled query always released.
/proc/vore_consent_refusal(requirement_type, mob/living/pred, mob/living/prey)
	if(!ispath(requirement_type, /datum/entry/part/req/vore_consent))
		CRASH("invalid native vore consent requirement")
	var/datum/entry/part/req/R = part_make(requirement_type)
	var/datum/act/op/acceptance/A = acceptance_act(prey, null, prey, null, pred)
	try
		op_menu_record_reads(R.read_keys(A))
		. = op_req_check(A, R)
	catch(var/exception/fault)
		acceptance_act_release(A)
		throw fault
	acceptance_act_release(A)

/// Effect-domain decision, derived from the actual null-or-reason requirement.
/proc/vore_consents(requirement_type, mob/living/pred, mob/living/prey)
	return isnull(vore_consent_refusal(requirement_type, pred, prey))


/datum/digest_mode
	/// The consent predicate this mode's effect needs from the prey, or null.
	var/consent

/// Why this mode won't act on `L` in belly `B`, or null.
/datum/digest_mode/proc/consent_refusal(obj/belly/B, mob/living/L)
	if(!consent)
		return null
	return vore_consent_refusal(consent, B.owner, L)

/datum/digest_mode/digest
	consent = /datum/entry/part/req/vore_consent/digest

/datum/digest_mode/absorb
	consent = /datum/entry/part/req/vore_consent/absorb

/datum/digest_mode/heal
	consent = /datum/entry/part/req/vore_consent/heal

/// Tells the predator, once as `L` arrives, why this belly's mode will only hold them.
/obj/belly/proc/show_mode_refusal(mob/living/L)
	var/datum/digest_mode/DM = GLOB.digest_modes["[digest_mode]"]
	var/reason = DM?.consent_refusal(src, L)
	if(reason && L.stat != DEAD && !L.absorbed)
		to_chat(owner, span_vnotice("Your [lowertext(name)] will only hold [L]: [reason]."))
