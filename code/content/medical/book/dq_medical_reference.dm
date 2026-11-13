// DQ Medical Reference — TGUI book documenting the cascading-condition
// system. Six tabs:
//
//   Conditions — each condition's clinical picture, cures, what causes
//                it (mixed: causes + upstream conditions), and what it
//                leads to (forward links to downstream conditions and
//                organ-damage outcomes).
//   Symptoms   — symptom catalogue with audiences, scanner phrases,
//                examine lines, and the conditions they appear in.
//   Reagents   — every cure/contraindicated reagent grouped by use.
//   Triggers   — every /datum/affliction_trigger (injury events, organ
//                integrity thresholds, blood loss, infection thresholds,
//                metrics) and what each produces.
//   Purity     — the four grades and their purity bands, every contaminant, and
//                the recipes that ask for a minimum grade.
//   Surgeries  — every procedure, its steps, tools, the conditions it
//                treats, and (where applicable) which organs it repairs.
//
// Each tab's data builder lives in its own *_tab.dm file in this
// directory; the tgui_data shell below dispatches to them. Builders read
// long-lived prototypes via dq_proto() (see .../proto_cache.dm)
// so the book renders without re-allocating every subtype on each open.


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
	op("read_reference", in_hand(), label("Read"), opens_ui())
	interface("DQMedicalBook", state = nameof(GLOB.tgui_physical_state))
	without("ui_open")
	ui_shape(conditions = any, symptoms = any, reagents = any, causes = any, surgeries = any, purity = any)

/// /obj/item/book/dq_medical_reference's window data: none that changes. The book's text is the same for every reader and every copy for the
/// life of the world (it is built from the condition prototypes), so it is sent once per open as static data, built once per world.
/obj/item/book/dq_medical_reference/ui_data(datum/act/eval/A)
	return list()

/obj/item/book/dq_medical_reference/ui_static_data(datum/act/eval/A)
	return CACHED_KEY(dq_medical_book_data, "book", src)

/// The whole book (about 550 KB of text, 235 ms to build): every tab's entries.
DECLARE_SHARED_CACHE(dq_medical_book_data, GLOBAL_PROC_REF(build_dq_medical_book_data), SC_NEVER)

/proc/build_dq_medical_book_data(obj/item/book/dq_medical_reference/book)
	var/list/data = list()
	data["conditions"] = book._dq_book_conditions()
	data["symptoms"]   = book._dq_book_symptoms()
	data["reagents"]   = book._dq_book_reagents()
	data["causes"]     = book._dq_book_causes()
	data["surgeries"]  = book._dq_book_surgeries()
	data["purity"]     = book._dq_book_purity()
	return data
