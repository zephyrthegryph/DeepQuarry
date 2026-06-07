// /datum/medical_symptom — observable presentation of a condition.
//
// A symptom is an *expression* of a condition's effect on the body.
// One condition has a weighted pool of symptoms; on creation (and at
// severity milestones) the condition rolls which symptoms are active.
// The symptom is what the patient feels, what bystanders see, and what
// the scanner reports — not the condition itself.
//
// Three independent audience flags decide who learns what:
//   SYMPTOM_AUDIENCE_PATIENT — the player gets occasional chat
//     messages narrating subjective sensations. Lost when unconscious.
//   SYMPTOM_AUDIENCE_PUBLIC  — emotes that surrounding mobs see.
//   SYMPTOM_AUDIENCE_SCANNER — strings that the body scanner can pick
//     up when reading the patient.
//
// Symptoms don't tick severity. They're a presentation layer that
// reads off the parent condition. They CAN cause minor mechanical
// effects (a "vertigo" symptom might apply a small slowdown), but
// anything load-bearing belongs on the condition itself.
/datum/medical_symptom
	/// Display name in scanner UI when the symptom is scanner-visible.
	var/name = "symptom"
	/// Bitfield of SYMPTOM_AUDIENCE_*.
	var/audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC

	/// % chance per Life() tick to fire a patient drip message while
	/// the patient is conscious. The actual message list is shared
	/// across all instances of a symptom subtype via the per-type
	/// proc `get_patient_messages()`.
	var/patient_message_chance = 4

	/// % chance per Life() tick to fire a public emote. Emotes live
	/// in `get_public_emotes()` — one shared list per symptom subtype.
	var/public_emote_chance = 3

	/// The phrase the scanner reads when this symptom is active.
	/// Free-form, e.g. "dry cough", "elevated breathing rate".
	var/scanner_phrase

	/// Third-person clinical description used by reference materials.
	/// Where `patient_messages` are first-person flavour ("You feel
	/// uncomfortably warm"), this is what a doctor reading a textbook
	/// would see ("Sensation of warmth across the body, often without
	/// elevated skin temperature").
	var/clinical_description

	/// Reference-book category. Symptoms are grouped by visibility:
	///   "Subjective" — felt only by the patient (pain, dizziness)
	///   "Observable" — visible to anyone looking (pallor, bleeding,
	///                  laboured breathing)
	///   "Diagnosable" — picked up only with a scanner or instrument
	///                  (e.g. measurable abdominal tenderness)
	/// A symptom can sensibly belong to several; we pick the dominant
	/// one for grouping, since the book also shows the audience list.
	var/category = "Subjective"
	/// Optional finer grouping rendered as a grey subheader in the
	/// book index. Use for theme clusters (e.g. "Pain" / "Vision" /
	/// "Breathing"). Null = no subgroup.
	var/subcategory

	/// Line shown on the patient's `examine` output when this symptom is
	/// active and externally visible (audiences includes _PUBLIC). The
	/// string is rendered as-is; the helper does NOT prepend "you see"
	/// or similar, so write a full short sentence: "They are bleeding
	/// heavily from a limb." Null = fall back to the symptom name.
	var/examine_line

	/// Back-reference to the condition that spawned us. Set in
	/// /datum/medical_issue/condition/proc/roll_symptoms.
	var/datum/medical_issue/condition/source_condition

/// Per-type content procs. Each subtype overrides these to return a
/// `var/static/list/` local — DM initializes the static once per
/// subtype on first call, and every instance of that subtype shares
/// the same list reference. The base returns null on both, which
/// means subtypes with no patient or public channel don't allocate
/// anything at all.
///
/// This is how we get "static per subtype" content in DM despite the
/// language not allowing storage-class overrides on inherited vars.
/// The cost is one extra proc call per read instead of a direct field
/// access, which is negligible compared to a list allocation per
/// instance.
/datum/medical_symptom/proc/get_patient_messages()
	return null

/datum/medical_symptom/proc/get_public_emotes()
	return null

/datum/medical_symptom/proc/on_present(mob/living/M, datum/medical_issue/condition/source)
	if(!M)
		return
	// Initial announcement — a single message when the symptom first
	// appears, on top of the regular drip.
	var/list/msgs = get_patient_messages()
	if((audiences & SYMPTOM_AUDIENCE_PATIENT) && length(msgs))
		send_patient_message(M, initial = TRUE)

/datum/medical_symptom/proc/on_resolve(mob/living/M, datum/medical_issue/condition/source)
	// Override to undo any persistent effect (e.g. clear a status
	// effect, remove a movement modifier).
	return

/datum/medical_symptom/proc/tick(mob/living/M, datum/medical_issue/condition/source)
	if(!M)
		return
	// Patient drip: only while conscious. Unconscious patients lose
	// this channel entirely — by design.
	var/list/msgs = get_patient_messages()
	if((audiences & SYMPTOM_AUDIENCE_PATIENT) && length(msgs))
		if(M.stat == CONSCIOUS && prob(patient_message_chance))
			send_patient_message(M)
	var/list/emotes = get_public_emotes()
	if((audiences & SYMPTOM_AUDIENCE_PUBLIC) && length(emotes))
		if(prob(public_emote_chance))
			M.emote(pick(emotes))

/datum/medical_symptom/proc/send_patient_message(mob/living/M, initial = FALSE)
	var/list/msgs = get_patient_messages()
	if(!length(msgs))
		return
	var/msg = pick(msgs)
	to_chat(M, span_warning(msg))

/datum/medical_symptom/proc/is_scanner_visible()
	return (audiences & SYMPTOM_AUDIENCE_SCANNER) && scanner_phrase
