// DQ Medical Reference — TGUI book documenting the cascading-condition
// system. Five tabs:
//
//   Conditions — each condition's clinical picture, cures, what causes
//                it (mixed: causes + upstream conditions), and what it
//                leads to (forward links to downstream conditions and
//                organ-damage outcomes).
//   Symptoms   — symptom catalogue with audiences, scanner phrases,
//                examine lines, and the conditions they appear in.
//   Reagents   — every cure/contraindicated reagent grouped by use.
//   Causes     — every non-condition cause (damage events, organ-damage
//                thresholds, blood loss, infection thresholds) and what
//                each produces.
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

/obj/item/book/dq_medical_reference/attack_self(mob/user)
	. = ..()
	tgui_interact(user)

/obj/item/book/dq_medical_reference/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/obj/item/book/dq_medical_reference/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DQMedicalBook", name)
		ui.open()

/obj/item/book/dq_medical_reference/tgui_data(mob/user)
	var/list/data = list()
	data["conditions"] = _dq_book_conditions()
	data["symptoms"]   = _dq_book_symptoms()
	data["reagents"]   = _dq_book_reagents()
	data["causes"]     = _dq_book_causes()
	data["surgeries"]  = _dq_book_surgeries()
	return data
