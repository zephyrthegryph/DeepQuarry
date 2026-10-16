STATIC_ENTRY(speech_presentation)

/proc/speech_presentation(bubble_icon = null)
	return entry_make(ENTRY_SPEECH_PRESENTATION, null, list("bubble_icon" = bubble_icon))

/datum/type_trait/speech_presentation
	var/bubble_icon = "normal"

/datum/type_trait/speech_presentation/copy_values(datum/type_trait/speech_presentation/into)
	into.bubble_icon = bubble_icon

/datum/entry_engine/type_trait/speech_presentation
	kind = ENTRY_SPEECH_PRESENTATION
	trait_type = /datum/type_trait/speech_presentation
	publish_key = SPEECH_PRESENTATION_KEY
	base_type = /atom
	var_names = list("bubble_icon" = "bubble_icon")

READS_AS(/proc/speech_presentation_of, SPEECH_PRESENTATION_KEY)
/proc/speech_presentation_of(atom/holder) as /datum/type_trait/speech_presentation
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_SPEECH_PRESENTATION)

/proc/speech_presentation_of_type(path) as /datum/type_trait/speech_presentation
	READS_FROM()
	return type_trait_of_type(path, ENTRY_SPEECH_PRESENTATION)
