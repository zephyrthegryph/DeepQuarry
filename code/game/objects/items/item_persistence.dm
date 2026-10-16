// Item bank admission and cryostorage retention are type policy with holder-local overrides.
STATIC_ENTRY(item_persistence)
/proc/item_persistence(preserve = null)
	return entry_make(ENTRY_ITEM_PERSISTENCE, null, list("preserve" = preserve))
/datum/type_trait/item_persistence
	var/preserve = FALSE
/datum/type_trait/item_persistence/copy_values(datum/type_trait/item_persistence/into)
	into.preserve = preserve
/datum/entry_engine/type_trait/item_persistence
	kind = ENTRY_ITEM_PERSISTENCE
	trait_type = /datum/type_trait/item_persistence
	publish_key = ITEM_PERSISTENCE_KEY
	base_type = /obj/item
	var_names = list("preserve_item" = "preserve")
READS_AS(/proc/persistence_of, ITEM_PERSISTENCE_KEY)
/proc/persistence_of(obj/item/I) as /datum/type_trait/item_persistence
	READS_FROM(I)
	return type_trait_of(I, ENTRY_ITEM_PERSISTENCE)
/proc/persistence_of_type(type) as /datum/type_trait/item_persistence
	READS_FROM()
	return type_trait_of_type(type, ENTRY_ITEM_PERSISTENCE)
/obj/item/proc/set_preserve_item(value)
	return set_trait(src, ENTRY_ITEM_PERSISTENCE, "preserve", value)
