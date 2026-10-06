//Step three - drying
/obj/item/stack/wetleather/get_mechanics_info(list/additional_information)
	return ..(list("Dry it to finish tanning: under a " + span_bold(span_red("fire")) + ", in a " + span_bold(span_blue("drying rack")) + \
		", or on a " + span_bold(span_brown("tanning rack")) + " built from steel or wooden boards.") + additional_information)

/obj/item/stack/wetleather
	name = "wet leather"
	desc = "This leather has been cleaned but still needs to be dried."
	singular_name = "wet leather piece"
	icon_state = "sheet-wetleather"
	var/drying_threshold_temperature = 500 //Kelvin to start drying
	no_variants = FALSE
	max_amount = 20
	stacktype = "wetleather"

	var/dry_type = /obj/item/stack/material/leather

/// Reduced when exposed to high temperatures; 0 is dry. A tanning rack reads it through its
/// "drying.wetness" derived input.
/obj/item/stack/wetleather/var/wetness = 30
TRACKED_BRIDGED(/obj/item/stack/wetleather, wetness, CHANGE_EXPLICIT)

/obj/item/stack/wetleather/examine(mob/user)
	. = ..()
	. += "\The [src] is [get_dryness_text()]."

/obj/item/stack/wetleather/proc/get_dryness_text()
	if(wetness > 20)
		return "wet"
	if(wetness > 10)
		return "damp"
	if(wetness)
		return "almost dry"
	return "dry"

/// Heat behaviour rule: ten seconds at 500 K dries it.
/obj/item/stack/wetleather/proc/rule_dry(datum/rule/rule)
	dry()

/obj/item/stack/wetleather/proc/dry()
	var/obj/item/stack/material/leather/L = new(src.loc, get_amount())
	use(get_amount())
	return L

/obj/item/stack/wetleather/transfer_to(obj/item/stack/S, tamount=null, type_verified)
	. = ..()
	if(.) // If it transfers any, do a weighted average of the wetness
		var/obj/item/stack/wetleather/W = S
		var/oldamt = W.amount - .
		W.set_wetness(round(((oldamt * W.wetness) + (. * wetness)) / W.amount))
