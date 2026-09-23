// Wearable tags: one per slot_flags bit, so equip slot constraints are
// predicates (TAG_WEAR_HEAD, TAG_POCKETABLE, ...). The type value comes from
// initial(slot_flags); instances read their current slot_flags, since some
// items change them at runtime (folding stocks, shield modes, chewables).

/datum/property_provider/type_var/tag/slot_flag
	applies_to = /obj/item
	/// SLOT_* bit.
	var/flag = 0

/datum/property_provider/type_var/tag/slot_flag/read_initial(path)
	var/obj/item/I = path
	return initial(I.slot_flags) & flag

/datum/property_provider/type_var/tag/slot_flag/instance_value(datum/D)
	var/obj/item/I = D
	return (I.slot_flags & flag) ? TRUE : FALSE

/datum/property_def/tag/wear_suit
	id = TAG_WEAR_SUIT
	name = "Wear suit"
	adjective = "worn as a suit"

/datum/property_provider/type_var/tag/slot_flag/wear_suit
	property = TAG_WEAR_SUIT
	flag = SLOT_OCLOTHING

/datum/property_def/tag/wear_uniform
	id = TAG_WEAR_UNIFORM
	name = "Wear uniform"
	adjective = "worn as a jumpsuit"

/datum/property_provider/type_var/tag/slot_flag/wear_uniform
	property = TAG_WEAR_UNIFORM
	flag = SLOT_ICLOTHING

/datum/property_def/tag/wear_gloves
	id = TAG_WEAR_GLOVES
	name = "Wear gloves"
	adjective = "worn on the hands"

/datum/property_provider/type_var/tag/slot_flag/wear_gloves
	property = TAG_WEAR_GLOVES
	flag = SLOT_GLOVES

/datum/property_def/tag/wear_eyes
	id = TAG_WEAR_EYES
	name = "Wear eyes"
	adjective = "worn over the eyes"

/datum/property_provider/type_var/tag/slot_flag/wear_eyes
	property = TAG_WEAR_EYES
	flag = SLOT_EYES

/datum/property_def/tag/wear_ears
	id = TAG_WEAR_EARS
	name = "Wear ears"
	adjective = "worn on an ear"

/datum/property_provider/type_var/tag/slot_flag/wear_ears
	property = TAG_WEAR_EARS
	flag = SLOT_EARS

/datum/property_def/tag/wear_two_ears
	id = TAG_WEAR_TWO_EARS
	name = "Wear two ears"
	adjective = "worn over both ears"

/datum/property_provider/type_var/tag/slot_flag/wear_two_ears
	property = TAG_WEAR_TWO_EARS
	flag = SLOT_TWOEARS

/datum/property_def/tag/wear_mask
	id = TAG_WEAR_MASK
	name = "Wear mask"
	adjective = "worn on the face"

/datum/property_provider/type_var/tag/slot_flag/wear_mask
	property = TAG_WEAR_MASK
	flag = SLOT_MASK

/datum/property_def/tag/wear_head
	id = TAG_WEAR_HEAD
	name = "Wear head"
	adjective = "worn on the head"

/datum/property_provider/type_var/tag/slot_flag/wear_head
	property = TAG_WEAR_HEAD
	flag = SLOT_HEAD

/datum/property_def/tag/wear_feet
	id = TAG_WEAR_FEET
	name = "Wear feet"
	adjective = "worn on the feet"

/datum/property_provider/type_var/tag/slot_flag/wear_feet
	property = TAG_WEAR_FEET
	flag = SLOT_FEET

/datum/property_def/tag/wear_id
	id = TAG_WEAR_ID
	name = "Wear id"
	adjective = "worn as an ID"

/datum/property_provider/type_var/tag/slot_flag/wear_id
	property = TAG_WEAR_ID
	flag = SLOT_ID

/datum/property_def/tag/wear_belt
	id = TAG_WEAR_BELT
	name = "Wear belt"
	adjective = "worn on a belt"

/datum/property_provider/type_var/tag/slot_flag/wear_belt
	property = TAG_WEAR_BELT
	flag = SLOT_BELT

/datum/property_def/tag/wear_back
	id = TAG_WEAR_BACK
	name = "Wear back"
	adjective = "worn on the back"

/datum/property_provider/type_var/tag/slot_flag/wear_back
	property = TAG_WEAR_BACK
	flag = SLOT_BACK

/datum/property_def/tag/wear_tie
	id = TAG_WEAR_TIE
	name = "Wear tie"
	adjective = "worn as an accessory"

/datum/property_provider/type_var/tag/slot_flag/wear_tie
	property = TAG_WEAR_TIE
	flag = SLOT_TIE

/datum/property_def/tag/pocketable
	id = TAG_POCKETABLE
	name = "Pocketable"
	adjective = "pocketable despite its size"

/datum/property_provider/type_var/tag/slot_flag/pocketable
	property = TAG_POCKETABLE
	flag = SLOT_POCKET

/datum/property_def/tag/no_pocket
	id = TAG_NO_POCKET
	name = "No pocket"
	adjective = "too awkward for a pocket"

/datum/property_provider/type_var/tag/slot_flag/no_pocket
	property = TAG_NO_POCKET
	flag = SLOT_DENYPOCKET

/datum/property_def/tag/holsterable
	id = TAG_HOLSTERABLE
	name = "Holsterable"
	adjective = "holsterable"

/datum/property_provider/type_var/tag/slot_flag/holsterable
	property = TAG_HOLSTERABLE
	flag = SLOT_HOLSTER

/datum/property_def/tag/wear_over
	id = TAG_WEAR_OVER
	name = "Worn over"
	desc = "Goes on over whatever already fills its equip slot."
	adjective = "worn over other things"

/datum/property_provider/type_var/tag/wear_over
	property = TAG_WEAR_OVER
	applies_to = /obj/item

/datum/property_provider/type_var/tag/wear_over/read_initial(path)
	return ispath(path, /obj/item/clothing/gloves) || ispath(path, /obj/item/clothing/shoes/magboots) || ispath(path, /obj/item/clothing/shoes/leg_guard)
