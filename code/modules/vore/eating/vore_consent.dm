// Vore consent as requirements (C7, doc/rewrite/rules.md §6 "vore consent").
//
// The prey's vore preferences are P2 predicate clauses, evaluated with the
// predator as actor and the prey as target, so every refusal has a reason:
//   - devouring (vore_sanity_checks) needs /datum/predicate/vore_devour;
//   - each digestion mode names the predicate its effect needs (`consent` on
//     /datum/digest_mode): a prey that refuses is held instead of processed;
//   - the stripping and worn-item addons need the prey's stripping and
//     contamination preferences.
// A mode is a rule: its trigger is the belly cycle (a rate over time, see
// belly_slot.dm), its condition is its consent predicate, its effect is
// process_mob().

// ---- Clause procs: called on the subject with (actor, target, held) ----

/mob/living/proc/vore_pref_devourable(mob/actor, atom/target, obj/item/held)
	return devourable

/mob/living/proc/vore_pref_digestable(mob/actor, atom/target, obj/item/held)
	return digestable

/mob/living/proc/vore_pref_absorbable(mob/actor, atom/target, obj/item/held)
	return absorbable

/mob/living/proc/vore_pref_healbelly(mob/actor, atom/target, obj/item/held)
	return permit_healbelly

/mob/living/proc/vore_pref_strippable(mob/actor, atom/target, obj/item/held)
	return strip_pref

/mob/living/proc/vore_pref_contaminable(mob/actor, atom/target, obj/item/held)
	return contaminate_pref

/mob/living/proc/vore_not_absorbed(mob/actor, atom/target, obj/item/held)
	return !absorbed

/mob/living/proc/vore_not_dead(mob/actor, atom/target, obj/item/held)
	return stat != DEAD

// ---- Predicates ----

/// Being eaten at all.
/datum/predicate/vore_devour
	name = "devour"
	spec = list(
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_pref_devourable, null), "They aren't able to be devoured."),
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_not_absorbed, null), "They aren't in a state to be devoured."),
		REQ_BECAUSE(REQ_ON(PRED_ACTOR, /mob/living/proc/vore_not_absorbed, null), "They aren't in a state to be devoured."),
	)

/// Digest mode: the prey allows digestion and is not already absorbed.
/datum/predicate/vore_digest
	name = "digest"
	spec = list(
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_pref_digestable, null), "they don't allow digestion"),
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_not_absorbed, null), "they are already absorbed"),
	)

/// Absorb mode: the prey allows absorption and is not already absorbed.
/datum/predicate/vore_absorb
	name = "absorb"
	spec = list(
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_pref_absorbable, null), "they don't allow absorption"),
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_not_absorbed, null), "they are already absorbed"),
	)

/// Heal mode: the prey allows heal bellies and is alive.
/datum/predicate/vore_heal
	name = "heal"
	spec = list(
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_pref_healbelly, null), "they don't allow healing bellies"),
		REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_not_dead, null), "they are dead"),
	)

/// The stripping addon.
/datum/predicate/vore_strip
	name = "strip"
	spec = list(REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_pref_strippable, null), "they don't allow stripping"))

/// The worn-items addon.
/datum/predicate/vore_affect_worn
	name = "affect worn items"
	spec = list(REQ_BECAUSE(REQ_ON(PRED_TARGET, /mob/living/proc/vore_pref_contaminable, null), "they don't allow their worn items to be affected"))

// ---- Reads ----

/// Why `pred` can't `kind` (a /datum/predicate/vore_* path) `prey`, or null if it can.
/proc/vore_consent_refusal(predicate_path, mob/living/pred, mob/living/prey)
	var/datum/predicate/P = PREDICATE(predicate_path)
	return PREDICATE_REASON(P, pred, prey, null)

/// TRUE if `prey` consents to `predicate_path` from `pred`.
/proc/vore_consents(predicate_path, mob/living/pred, mob/living/prey)
	var/datum/predicate/P = PREDICATE(predicate_path)
	return PREDICATE_PASSES(P, pred, prey, null)

/datum/digest_mode
	/// The consent predicate this mode's effect needs from the prey, or null.
	var/consent

/// Why this mode won't act on `L` in belly `B`, or null.
/datum/digest_mode/proc/consent_refusal(obj/belly/B, mob/living/L)
	if(!consent)
		return null
	return vore_consent_refusal(consent, B.owner, L)

/datum/digest_mode/digest
	consent = /datum/predicate/vore_digest

/datum/digest_mode/absorb
	consent = /datum/predicate/vore_absorb

/datum/digest_mode/heal
	consent = /datum/predicate/vore_heal

/// Tells the predator, once as `L` arrives, why this belly's mode will only hold them.
/obj/belly/proc/show_mode_refusal(mob/living/L)
	var/datum/digest_mode/DM = GLOB.digest_modes["[digest_mode]"]
	var/reason = DM?.consent_refusal(src, L)
	if(reason && L.stat != DEAD && !L.absorbed)
		to_chat(owner, span_vnotice("Your [lowertext(name)] will only hold [L]: [reason]."))
