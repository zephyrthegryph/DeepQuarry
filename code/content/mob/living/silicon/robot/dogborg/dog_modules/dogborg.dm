/obj/item/lightreplacer/dogborg
	name = "light replacer"
	desc = "A device to automatically replace lights. This version is capable to produce a few replacements using your internal matter reserves."
	max_uses = 16
	uses = 10
	var/datum/matter_synth/glass = null
	special_handling = TRUE

/// Using it in the hand asks what to do: check the reserves (and fabricate a light from them), or change the colour of the lights it makes.
CAPABILITIES(/obj/item/lightreplacer/dogborg)
	ref_one(nameof(glass), /datum/matter_synth)
	click_order(BIND_IN_HAND, "choose", "colour")
	op("choose", in_hand(), label("Reserves or colour"),
		asks(/datum/prompt/choice, fields = list("question" = "Do you wish to check the reserves or change the color?", "title" = "Selection List", "choices" = list("Reserves", "Color"), "buttons" = TRUE)),
		then(PROC_REF(dogborg_chosen)))
	op("pick_colour", ai(), wait(0), asks(/datum/prompt/color, fields = list("question" = "Choose a color to set the light to! (Default is [LIGHT_COLOR_INCANDESCENT_TUBE])", "default" = nameof(selected_color))), then(PROC_REF(colour_asked)))
	op("fabricate", ai(), needs(req(PROC_REF(has_room), because = MSG(lightreplacer/full)), req(PROC_REF(enough_reserves))), wait(5 SECONDS), then(PROC_REF(fabricated)))

/obj/item/lightreplacer/dogborg/proc/has_reserves()
	return glass && glass.energy >= 125

/// "Color" opens the picker (the replacer's colour step), "Reserves" gives (the count, then a light fabricated from the matter reserves while the borg stands still).
/obj/item/lightreplacer/dogborg/proc/dogborg_chosen(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/choice/picked = A.answer
	if(picked?.value == "Color")
		perform_op(user, src, "pick_colour", null, ORIGIN_AI, AUTH_AI)
		return OP_OK
	if(uses >= max_uses)
		to_chat(user, span_warning("[src.name] is full."))
		return OP_OK
	if(!has_reserves())
		to_chat(user, span_warning("Insufficient material reserves."))
		return OP_OK
	to_chat(user, span_filter_notice("It has [uses] lights remaining. Attempting to fabricate a replacement. Please stand still."))
	perform_op(user, src, "fabricate", null, ORIGIN_AI, AUTH_AI)
	return OP_OK

MSG_DEF_SELF(lightreplacer/no_reserves, "Insufficient material reserves.")

/obj/item/lightreplacer/dogborg/proc/enough_reserves(datum/act/op/A)
	return has_reserves() ? null : MSG(lightreplacer/no_reserves)

/obj/item/lightreplacer/dogborg/proc/fabricated(datum/act/op/A)
	if(!has_reserves())
		log_world("DOGBORG: [src] fabricate ran without reserves")
		return OP_FAILED
	glass.use_charge(125)
	add_uses(1)
	return OP_OK
