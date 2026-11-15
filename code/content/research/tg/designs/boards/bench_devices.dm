// Circuit boards of the small bench and lab devices that used to be mapped or spawned without a way to build or dismantle them (the boards are rows of
// code/content/variants/circuitboards.dm, or plain board types for the processors).

/datum/design_techweb/board/bookbinder
	SET_CIRCUIT_DESIGN_NAMEDESC("book binder")
	id = "bookbinder"
	build_path = VARIANT(/obj/item/circuitboard/bookbinder)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_SERVICE
	)
	departmental_flags = DEPARTMENT_BITFLAG_SERVICE | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/libraryscanner
	SET_CIRCUIT_DESIGN_NAMEDESC("book scanner")
	id = "libraryscanner"
	build_path = VARIANT(/obj/item/circuitboard/libraryscanner)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_SERVICE
	)
	departmental_flags = DEPARTMENT_BITFLAG_SERVICE | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/colormate
	SET_CIRCUIT_DESIGN_NAMEDESC("color mate")
	id = "colormate"
	build_path = VARIANT(/obj/item/circuitboard/colormate)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_SERVICE
	)
	departmental_flags = DEPARTMENT_BITFLAG_SERVICE | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/icecream_vat
	SET_CIRCUIT_DESIGN_NAMEDESC("icecream vat")
	id = "icecream_vat"
	build_path = VARIANT(/obj/item/circuitboard/icecream_vat)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_SERVICE
	)
	departmental_flags = DEPARTMENT_BITFLAG_SERVICE | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/bunsen_burner
	SET_CIRCUIT_DESIGN_NAMEDESC("bunsen burner")
	id = "bunsen_burner"
	build_path = VARIANT(/obj/item/circuitboard/bunsen_burner)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_CHEMISTRY
	)
	departmental_flags = DEPARTMENT_BITFLAG_MEDICAL | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/microscope
	SET_CIRCUIT_DESIGN_NAMEDESC("electron microscope")
	id = "microscope"
	build_path = VARIANT(/obj/item/circuitboard/microscope)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_RESEARCH
	)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/radiocarbon_spectrometer
	SET_CIRCUIT_DESIGN_NAMEDESC("radiocarbon spectrometer")
	id = "radiocarbon_spectrometer"
	build_path = VARIANT(/obj/item/circuitboard/radiocarbon_spectrometer)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_RESEARCH
	)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/optable
	SET_CIRCUIT_DESIGN_NAMEDESC("operating table")
	id = "optable"
	build_path = VARIANT(/obj/item/circuitboard/optable)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_MEDICAL
	)
	departmental_flags = DEPARTMENT_BITFLAG_MEDICAL | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/scale
	SET_CIRCUIT_DESIGN_NAMEDESC("scale")
	id = "scale"
	build_path = VARIANT(/obj/item/circuitboard/scale)
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_MEDICAL
	)
	departmental_flags = DEPARTMENT_BITFLAG_MEDICAL | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/slime_processor
	SET_CIRCUIT_DESIGN_NAMEDESC("slime processor")
	id = "slime_processor"
	build_path = /obj/item/circuitboard/processor
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_RESEARCH
	)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/monkey_processor
	SET_CIRCUIT_DESIGN_NAMEDESC("monkey processor")
	id = "monkey_processor"
	build_path = /obj/item/circuitboard/processor/monkey
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_RESEARCH
	)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE
