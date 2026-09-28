/// Marks clothing as radiation protected (was /datum/element/radiation_protected_clothing).
/// A shared behaviour singleton: adds TRAIT_RADIATION_PROTECTED_CLOTHING while attached
/// and a line to the examine text. Attach with om_attach(clothing, /datum/om/behaviour/radiation_protected_clothing).
/datum/om/behaviour/radiation_protected_clothing
	handles = list(/datum/om/event/examine)

#define RADIATION_PROTECTED_TRAIT_SOURCE "radiation_protected_clothing_behaviour"

/datum/om/behaviour/radiation_protected_clothing/on_start(obj/item/clothing/C)
	add_trait(C, TRAIT_RADIATION_PROTECTED_CLOTHING, RADIATION_PROTECTED_TRAIT_SOURCE)

/datum/om/behaviour/radiation_protected_clothing/on_stop(obj/item/clothing/C)
	remove_trait(C, TRAIT_RADIATION_PROTECTED_CLOTHING, RADIATION_PROTECTED_TRAIT_SOURCE)

/datum/om/behaviour/radiation_protected_clothing/on_examine(obj/item/clothing/C, datum/om/event/examine/event)
	event.texts += span_notice("A patch with a hazmat sign on the side suggests it would <b>protect you from radiation</b>.")

#undef RADIATION_PROTECTED_TRAIT_SOURCE
