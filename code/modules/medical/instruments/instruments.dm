// Diagnostic instruments: each one outputs a single raw measurement
// with no interpretation. The player decides what's normal.
//
// All four follow the same /attack() pattern as the upstream health
// analyzer — click on a mob with the instrument in your hand. A short
// do_after delay simulates the time it takes to take the reading; the
// doctor is committed to the action during that window.

// (Stethoscope: upstream's /obj/item/clothing/accessory/stethoscope
// already does qualitative auscultation with organ-specific sounds —
// "muffled heart sounds", "wheezing respiration", etc. We don't ship a
// duplicate.)

// --- Thermometer ---
// Outputs raw celsius. No "fever / normal / hypothermic" tags.
/obj/item/thermometer_medical
	name = "medical thermometer"
	desc = "A small thermometer for taking a patient's body temperature."
	icon = 'icons/obj/device.dmi'
	icon_state = "health"
	w_class = ITEMSIZE_SMALL

MSG_DEF(thermometer_medical/taking, span_notice("You take %T%'s temperature."), span_notice("%U% takes %T%'s temperature."))
MSG_DEF_SELF(thermometer_medical/not_human, span_warning("You can't get a reading from this."))

CAPABILITIES(/obj/item/thermometer_medical)
	op("take", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(target_is_human), because = MSG(thermometer_medical/not_human))),
		begins(MSG(thermometer_medical/taking)), wait(3 SECONDS), then(PROC_REF(read_temperature)))

/// Requirement: the patient is a human.
/obj/item/thermometer_medical/proc/target_is_human(datum/act/op/A)
	return (ishuman(A.target)) ? null : MSG(thermometer_medical/not_human)

/obj/item/thermometer_medical/proc/read_temperature(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.target
	var/c = H.get_temperature_reading_c()
	to_chat(user, span_notice("Reading: <b>[c]°C</b>."))


// --- Blood pressure cuff ---
// Outputs systolic/diastolic as two numbers. 20-second hold to
// simulate inflating the cuff and listening for Korotkoff sounds.
/obj/item/bp_cuff
	name = "blood pressure cuff"
	desc = "A pressure cuff with an integrated gauge. Used to measure blood pressure."
	icon = 'icons/obj/device.dmi'
	icon_state = "health"
	w_class = ITEMSIZE_SMALL

MSG_DEF(bp_cuff/wrapping, span_notice("You wrap %I% around %T%'s arm and begin pumping."), span_notice("%U% starts wrapping %I% around %T%'s arm."))
MSG_DEF_SELF(bp_cuff/not_human, span_warning("You can't fit the cuff on this."))

CAPABILITIES(/obj/item/bp_cuff)
	op("take", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(target_is_human), because = MSG(bp_cuff/not_human))),
		begins(MSG(bp_cuff/wrapping)), wait(12 SECONDS), then(PROC_REF(read_pressure)))

/// Requirement: the patient is a human.
/obj/item/bp_cuff/proc/target_is_human(datum/act/op/A)
	return (ishuman(A.target)) ? null : MSG(bp_cuff/not_human)

/obj/item/bp_cuff/proc/read_pressure(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.target
	var/list/bp = H.get_bp_reading()
	if(!bp)
		to_chat(user, span_warning("You can't find a pulse to measure pressure against."))
		return
	to_chat(user, span_notice("Reading: <b>[bp[1]]/[bp[2]] mmHg</b>."))


// --- Pulse oximeter ---
// Clip-on for a finger. Outputs % saturation and a rough pulse confirm.
/obj/item/pulse_oximeter
	name = "pulse oximeter"
	desc = "A clip-on sensor that measures blood-oxygen saturation."
	icon = 'icons/obj/device.dmi'
	icon_state = "health"
	w_class = ITEMSIZE_SMALL

MSG_DEF(pulse_oximeter/clipping, span_notice("You clip %I% to %T%'s fingertip and wait for the reading."), span_notice("%U% clips %I% to %T%'s fingertip."))
MSG_DEF_SELF(pulse_oximeter/not_human, span_warning("You can't clip this to anything useful here."))

CAPABILITIES(/obj/item/pulse_oximeter)
	op("take", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(target_is_human), because = MSG(pulse_oximeter/not_human))),
		begins(MSG(pulse_oximeter/clipping)), wait(4 SECONDS), then(PROC_REF(read_oximetry)))

/// Requirement: the patient is a human.
/obj/item/pulse_oximeter/proc/target_is_human(datum/act/op/A)
	return (ishuman(A.target)) ? null : MSG(pulse_oximeter/not_human)

/obj/item/pulse_oximeter/proc/read_oximetry(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.target
	var/sat = H.get_o2_sat_reading()
	var/bpm = H.get_pulse_reading_bpm()
	if(!bpm)
		to_chat(user, span_warning("No signal — the device can't find a pulse."))
		return
	to_chat(user, span_notice("Reading: <b>SpO₂ [sat]%</b>, pulse <b>~[bpm] bpm</b>."))
