// Vore modes use the same pure, ordered native requirements as operations.
GLOBAL_DATUM_INIT(vore_consent_requirements, /datum/vore_consent_requirements, new)
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/vore_consent_requirements)
/datum/vore_consent_requirements

CAPABILITIES(/datum/vore_consent_requirements)
	acceptance(VORE_CONSENT_DEVOURABLE, req(PROC_REF(devourable_reason)), mode = ACCEPTANCE_REPLACE)
	acceptance(VORE_CONSENT_DEVOUR, req(PROC_REF(devourable_reason)), req_vore_unabsorbed(because = "They aren't in a state to be devoured."), req(PROC_REF(predator_unabsorbed_reason)), mode = ACCEPTANCE_REPLACE)
	acceptance(VORE_CONSENT_DIGEST, req(PROC_REF(digestable_reason)), req_vore_unabsorbed(), mode = ACCEPTANCE_REPLACE)
	acceptance(VORE_CONSENT_ABSORB, req(PROC_REF(absorbable_reason)), req_vore_unabsorbed(), mode = ACCEPTANCE_REPLACE)
	acceptance(VORE_CONSENT_HEAL, req(PROC_REF(healable_reason)), req(PROC_REF(alive_reason)), mode = ACCEPTANCE_REPLACE)
	acceptance(VORE_CONSENT_STRIP, req(PROC_REF(strippable_reason)), mode = ACCEPTANCE_REPLACE)
	acceptance(VORE_CONSENT_AFFECT_WORN, req(PROC_REF(worn_items_reason)), mode = ACCEPTANCE_REPLACE)

/// This target requirement is reused by devouring and both conversion modes.
/proc/req_vore_unabsorbed(because = null)
	return req(GLOBAL_PROC_REF(vore_unabsorbed_reason), because = because)

/proc/vore_unabsorbed_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && !prey.absorbed ? null : "they are already absorbed"

/datum/vore_consent_requirements/proc/devourable_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.vore_prefs.devourable ? null : "They aren't able to be devoured."

/datum/vore_consent_requirements/proc/predator_unabsorbed_reason(datum/act/op/A)
	var/mob/living/predator = A.actor
	return istype(predator) && !predator.absorbed ? null : "They aren't in a state to be devoured."

/datum/vore_consent_requirements/proc/digestable_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.vore_prefs.digestable ? null : "they don't allow digestion"

/datum/vore_consent_requirements/proc/absorbable_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.vore_prefs.absorbable ? null : "they don't allow absorption"

/datum/vore_consent_requirements/proc/healable_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.vore_prefs.permit_healbelly ? null : "they don't allow healing bellies"

/datum/vore_consent_requirements/proc/alive_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.stat != DEAD ? null : "they are dead"

/datum/vore_consent_requirements/proc/strippable_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.vore_prefs.strip_pref ? null : "they don't allow stripping"

/datum/vore_consent_requirements/proc/worn_items_reason(datum/act/op/A)
	var/mob/living/prey = A.target
	return istype(prey) && prey.vore_prefs.contaminate_pref ? null : "they don't allow their worn items to be affected"

/// Effect consumers keep a boolean view; the requirement itself returns a reason.
/proc/vore_consents(channel, mob/living/predator, mob/living/prey)
	return isnull(vore_consent_refusal(channel, predator, prey))

/proc/vore_consent_refusal(channel, mob/living/predator, mob/living/prey)
	if(!acceptance_declared(GLOB.vore_consent_requirements, channel))
		CRASH("Unknown vore consent requirement [channel]")
	return acceptance_reason(GLOB.vore_consent_requirements, channel, prey, prey, predator, predator, wearer_is_actor = TRUE)

/datum/digest_mode
	/// The native consent channel needed by this mode, or null.
	var/consent

/datum/digest_mode/proc/consent_refusal(obj/belly/B, mob/living/L)
	return consent ? vore_consent_refusal(consent, B.owner, L) : null

/datum/digest_mode/digest
	consent = VORE_CONSENT_DIGEST
/datum/digest_mode/absorb
	consent = VORE_CONSENT_ABSORB
/datum/digest_mode/heal
	consent = VORE_CONSENT_HEAL

/// Tells the predator why this mode will only hold the arriving prey.
/obj/belly/proc/show_mode_refusal(mob/living/L)
	var/datum/digest_mode/DM = GLOB.digest_modes["[digest_mode]"]
	var/reason = DM?.consent_refusal(src, L)
	if(reason && L.stat != DEAD && !L.absorbed)
		to_chat(owner, span_vnotice("Your [lowertext(name)] will only hold [L]: [reason]."))
