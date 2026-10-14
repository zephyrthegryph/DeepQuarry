/obj/structure/bookcase/manuals/xenoarchaeology
	name = "Xenoarchaeology Manuals bookcase"

CAPABILITIES(/obj/structure/bookcase/manuals/xenoarchaeology)
	initial_contents(/obj/item/book/manual/excavation)
	initial_contents(/obj/item/book/manual/mass_spectrometry)
	initial_contents(/obj/item/book/manual/materials_chemistry_analysis)
	initial_contents(/obj/item/book/manual/anomaly_testing)
	initial_contents(/obj/item/book/manual/anomaly_spectroscopy)
	initial_contents(/obj/item/book/manual/stasis)

/obj/machinery/alarm/isolation
	req_one_access = list(ACCESS_RESEARCH, ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)

/obj/machinery/alarm/monitor/isolation
	req_one_access = list(ACCESS_RESEARCH, ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
