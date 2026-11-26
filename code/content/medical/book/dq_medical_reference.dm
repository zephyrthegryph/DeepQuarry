// DQ Medical Reference: the medical half of the station wiki (code/content/wiki/). The book is a way into the wiki: reading it opens the wiki
// on the medical index. The data builders in this directory (one per kind: conditions, symptoms, reagents, triggers, surgery, purity) read the
// condition, reagent and surgery prototypes through dq_proto() (.../proto_cache.dm); the wiki's medical source (code/content/wiki/sources/medical.dm)
// turns their entries into articles. Everything is built once per world (dq_medical_book_data) and each article's body once, on first read.

/obj/item/book/dq_medical_reference
	name = "Doctor's Encyclopedia"
	desc = "A clinical reference covering every traceable cascading condition, its presentation, and pharmacological response."
	icon_state = "book7"
	title = "Doctor's Encyclopedia"
	author = "DQ Medical Authority"
	unique = TRUE
	libcategory = "Reference"
	special_handling = TRUE

CAPABILITIES(/obj/item/book/dq_medical_reference)
	op("read_reference", in_hand(), label("Read"), then(PROC_REF(read_reference)))

/// Reading the book opens the station wiki on its medical index.
/obj/item/book/dq_medical_reference/proc/read_reference(datum/act/op/A)
	wiki_open(A.actor, WIKI_ID_MEDICAL_INDEX)
	return OP_OK

/// The medical data (about 550 KB, 235 ms to build): every kind's entries, built once per world.
GLOBAL_TABLE(dq_medical_book_data, GLOBAL_PROC_REF(build_dq_medical_book_data))

/proc/dq_medical_book_data()
	return GLOBAL_TABLE_GET(dq_medical_book_data)

/proc/build_dq_medical_book_data()
	var/list/data = list()
	data["conditions"] = _dq_book_conditions()
	data["symptoms"]   = _dq_book_symptoms()
	data["reagents"]   = _dq_book_reagents()
	data["causes"]     = _dq_book_causes()
	data["surgeries"]  = _dq_book_surgeries()
	data["purity"]     = _dq_book_purity()
	return data
