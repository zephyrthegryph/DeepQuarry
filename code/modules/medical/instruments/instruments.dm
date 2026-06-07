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
	user.visible_message(
		span_notice("[user] takes [H]'s temperature."),
		span_notice("You take [H]'s temperature."),
	)
	if(!do_after(user, 3 SECONDS, H))
		return ITEM_INTERACT_SUCCESS
	var/c = H.get_temperature_reading_c()
	to_chat(user, span_notice("Reading: <b>[c]°C</b>."))
	return ITEM_INTERACT_SUCCESS


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
	user.visible_message(
		span_notice("[user] starts wrapping [src] around [H]'s arm."),
		span_notice("You wrap [src] around [H]'s arm and begin pumping."),
	)
	if(!do_after(user, 12 SECONDS, H))
		return ITEM_INTERACT_SUCCESS
	var/list/bp = H.get_bp_reading()
	if(!bp)
		to_chat(user, span_warning("You can't find a pulse to measure pressure against."))
		return ITEM_INTERACT_SUCCESS
	to_chat(user, span_notice("Reading: <b>[bp[1]]/[bp[2]] mmHg</b>."))
	return ITEM_INTERACT_SUCCESS


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
	user.visible_message(
		span_notice("[user] clips [src] to [H]'s fingertip."),
		span_notice("You clip [src] to [H]'s fingertip and wait for the reading."),
	)
	if(!do_after(user, 4 SECONDS, H))
		return ITEM_INTERACT_SUCCESS
	var/sat = H.get_o2_sat_reading()
	var/bpm = H.get_pulse_reading_bpm()
	if(!bpm)
		to_chat(user, span_warning("No signal — the device can't find a pulse."))
		return ITEM_INTERACT_SUCCESS
	to_chat(user, span_notice("Reading: <b>SpO₂ [sat]%</b>, pulse <b>~[bpm] bpm</b>."))
	return ITEM_INTERACT_SUCCESS
