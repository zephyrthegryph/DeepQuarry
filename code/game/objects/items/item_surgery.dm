// Surgical admission is item policy; changes publish through the native COW trait.
STATIC_ENTRY(item_surgery)
/proc/item_surgery(cavity_implantable = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_SURGERY, null, list("cavity_implantable" = cavity_implantable))
/datum/type_trait/item_surgery
	var/cavity_implantable = TRUE
/datum/type_trait/item_surgery/copy_values(datum/type_trait/item_surgery/into)
	into.cavity_implantable = cavity_implantable
/datum/entry_engine/type_trait/item_surgery
	kind = ENTRY_ITEM_SURGERY
	trait_type = /datum/type_trait/item_surgery
	publish_key = ITEM_SURGERY_KEY
	base_type = /obj/item
	var_names = list("cavity_implantable" = "cavity_implantable")
READS_AS(/proc/surgery_of, ITEM_SURGERY_KEY)
/proc/surgery_of(obj/item/I) as /datum/type_trait/item_surgery
	READS_FROM(I)
	return type_trait_of(I, ENTRY_ITEM_SURGERY)
/proc/surgery_of_type(type) as /datum/type_trait/item_surgery
	READS_FROM()
	return type_trait_of_type(type, ENTRY_ITEM_SURGERY)
/obj/item/proc/set_cavity_implantable(value)
	return set_trait(src, ENTRY_ITEM_SURGERY, "cavity_implantable", value)
