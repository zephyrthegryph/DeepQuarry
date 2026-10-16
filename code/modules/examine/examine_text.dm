// Native COW examine text: inherited type configuration and actual per-instance edits.
STATIC_ENTRY(examine_text)
/proc/examine_text(fluff = null, antag = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_EXAMINE_TEXT, null, list("fluff" = fluff, "antag" = antag))
/datum/type_trait/examine_text
	var/fluff
	var/antag
/datum/type_trait/examine_text/copy_values(datum/type_trait/examine_text/into)
	into.fluff = fluff
	into.antag = antag
/datum/entry_engine/type_trait/examine_text
	kind = ENTRY_EXAMINE_TEXT
	trait_type = /datum/type_trait/examine_text
	publish_key = EXAMINE_TEXT_KEY
	base_type = /atom
	var_names = list("description_fluff" = "fluff", "description_antag" = "antag")
READS_AS(/proc/examine_text_of, EXAMINE_TEXT_KEY)
/proc/examine_text_of(atom/A) as /datum/type_trait/examine_text
	READS_FROM(A)
	return type_trait_of(A, ENTRY_EXAMINE_TEXT)
/proc/examine_text_of_type(type) as /datum/type_trait/examine_text
	READS_FROM()
	return type_trait_of_type(type, ENTRY_EXAMINE_TEXT)
/atom/proc/set_description_fluff(value)
	return set_trait(src, ENTRY_EXAMINE_TEXT, "fluff", value)
/atom/proc/set_description_antag(value)
	return set_trait(src, ENTRY_EXAMINE_TEXT, "antag", value)
