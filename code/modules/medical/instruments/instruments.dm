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

/obj/item/thermometer_medical/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!ishuman(M))
		to_chat(user, span_warning("You can't get a reading from this."))
		return ITEM_INTERACT_SUCCESS
	var/mob/living/carbon/human/H = M
	act_message(user, H, MSG_SELF(span_notice("You take %T%'s temperature.")), MSG_OTHERS(span_notice("%U% takes %T%'s temperature.")))
	task_timed(user, 3 SECONDS, H, src, PROC_REF(read_temperature), list(user, H))
	return ITEM_INTERACT_SUCCESS

/obj/item/thermometer_medical/proc/read_temperature(mob/living/user, mob/living/carbon/human/H)
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

/obj/item/bp_cuff/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!ishuman(M))
		to_chat(user, span_warning("You can't fit the cuff on this."))
		return ITEM_INTERACT_SUCCESS
	var/mob/living/carbon/human/H = M
	act_message(user, src, MSG_SELF(span_notice("You wrap %T% around [H]'s arm and begin pumping.")), \
		MSG_OTHERS(span_notice("%U% starts wrapping %T% around [H]'s arm.")))
	task_timed(user, 12 SECONDS, H, src, PROC_REF(read_pressure), list(user, H))
	return ITEM_INTERACT_SUCCESS

/obj/item/bp_cuff/proc/read_pressure(mob/living/user, mob/living/carbon/human/H)
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

/obj/item/pulse_oximeter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!ishuman(M))
		to_chat(user, span_warning("You can't clip this to anything useful here."))
		return ITEM_INTERACT_SUCCESS
	var/mob/living/carbon/human/H = M
	act_message(user, src, MSG_SELF(span_notice("You clip %T% to [H]'s fingertip and wait for the reading.")), \
		MSG_OTHERS(span_notice("%U% clips %T% to [H]'s fingertip.")))
	task_timed(user, 4 SECONDS, H, src, PROC_REF(read_oximetry), list(user, H))
	return ITEM_INTERACT_SUCCESS

/obj/item/pulse_oximeter/proc/read_oximetry(mob/living/user, mob/living/carbon/human/H)
	var/sat = H.get_o2_sat_reading()
	var/bpm = H.get_pulse_reading_bpm()
	if(!bpm)
		to_chat(user, span_warning("No signal — the device can't find a pulse."))
		return
	to_chat(user, span_notice("Reading: <b>SpO₂ [sat]%</b>, pulse <b>~[bpm] bpm</b>."))
