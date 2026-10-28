// REF(): the one primitive that builds a reference text, for a request-local href or a locate() in the same request. Never stored (lint ref_text).
// \ref behaviour got changed in 512, so this replicates the old behaviour for tagged datums.
/proc/REF(input)
	READS_FROM() // the text of a reference (its tag flag is bookkeeping for the text, not an input of a value)
	if(istype(input, /datum))
		var/datum/thing = input
		if(thing.datum_flags & DF_USE_TAG)
			if(!thing.tag)
				thing.datum_flags &= ~DF_USE_TAG
				stack_trace("A ref was requested of an object with DF_USE_TAG set but no tag: [thing]")
			else
				return "\[[url_encode(thing.tag)]\]"
	return ref(input)
