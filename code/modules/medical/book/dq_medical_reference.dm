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
//   Triggers   — every /datum/affliction_trigger (injury events, organ
//                integrity thresholds, blood loss, infection thresholds,
//                metrics) and what each produces.
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

EXTEND_INTERACTIONS(/obj/item/book/dq_medical_reference, INTERACT_USE("Read", PROC_REF(interaction_read_reference)))

/// Old attack_self.
/obj/item/book/dq_medical_reference/proc/interaction_read_reference(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)

DECLARE_UI_STATE(/obj/item/book/dq_medical_reference, GLOB.tgui_physical_state)

DECLARE_UI(/obj/item/book/dq_medical_reference, "DQMedicalBook")

UI_DATA_REPLACE(/obj/item/book/dq_medical_reference, "merge:ui_data_obj_item_book_dq_medical_reference{conditions:unknown,symptoms:unknown,reagents:unknown,causes:unknown,surgeries:unknown}")

/// The computed part of /obj/item/book/dq_medical_reference's window data (declared on its UI_DATA row).
/obj/item/book/dq_medical_reference/proc/ui_data_obj_item_book_dq_medical_reference(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["conditions"] = _dq_book_conditions()
	data["symptoms"]   = _dq_book_symptoms()
	data["reagents"]   = _dq_book_reagents()
	data["causes"]     = _dq_book_causes()
	data["surgeries"]  = _dq_book_surgeries()
	return data
