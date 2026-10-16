STATIC_ENTRY(object_break_config)

/proc/object_break_config(debris_type = null, debris_amount = null, broken_icon_state = null)
	return entry_make(ENTRY_OBJECT_BREAK_CONFIG, null, list("debris_type" = debris_type, "debris_amount" = debris_amount, "broken_icon_state" = broken_icon_state))

/datum/type_trait/object_break_config
	var/debris_type = null
	var/debris_amount = 1
	var/broken_icon_state = null

/datum/type_trait/object_break_config/copy_values(datum/type_trait/object_break_config/into)
	into.debris_type = debris_type
	into.debris_amount = debris_amount
	into.broken_icon_state = broken_icon_state

/datum/entry_engine/type_trait/object_break_config
	kind = ENTRY_OBJECT_BREAK_CONFIG
	trait_type = /datum/type_trait/object_break_config
	publish_key = OBJECT_BREAK_CONFIG_KEY
	base_type = /obj
	var_names = list("debris_type" = "debris_type", "debris_amount" = "debris_amount", "broken_icon_state" = "broken_icon_state")

READS_AS(/proc/object_break_config_of, OBJECT_BREAK_CONFIG_KEY)
/proc/object_break_config_of(obj/holder) as /datum/type_trait/object_break_config
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_OBJECT_BREAK_CONFIG)

/proc/object_break_config_of_type(path) as /datum/type_trait/object_break_config
	READS_FROM()
	return type_trait_of_type(path, ENTRY_OBJECT_BREAK_CONFIG)
