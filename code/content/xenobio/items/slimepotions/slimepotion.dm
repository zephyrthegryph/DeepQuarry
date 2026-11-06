// These things get applied to slimes to do things.

/obj/item/slimepotion
	name = "slime agent"
	desc = "A flask containing strange, mysterious substances excreted by a slime."
	icon = 'icons/obj/chemical.dmi'
	w_class = ITEMSIZE_TINY

// This is actually applied to an extract, so no attack() overriding needed.
/obj/item/slimepotion/enhancer/get_mechanics_info(list/additional_information)
	return ..(list("This will even work on inert slime extracts, if it wasn't enhanced before. Extracts enhanced cannot be enhanced again.") + additional_information)

/obj/item/slimepotion/enhancer
	name = "extract enhancer agent"
	desc = "A potent chemical mix that will give a slime extract an additional two uses."
	icon_state = "potcyan"

CAPABILITIES(/obj/item/slimepotion)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/slimepotion/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/slimepotion/mimic))
		if(!consume(O, user))
			return OP_DECLINE
		to_chat(user, span_notice("You apply the mimic to the slime potion as it copies it's effects."))
		play_sfx(src, SFX_EFFECTS_BUBBLES)
		var/newtype = src.type
		new newtype(get_turf(src))
	return OP_DECLINE

/obj/item/slimepotion/reinvigoration/get_mechanics_info(list/additional_information)
	return ..(list("This will even work on inert extracts. The extract is destroyed in the process.") + additional_information)

/obj/item/slimepotion/reinvigoration
	name = "extract reinvigoration agent"
	desc = "A potent chemical mix that will create a slime of appropriate type out of an extract."
	icon_state = "potcyan"
