// Compare only this batch's affected type trees, including their recorded subtypes.
/datum/unit_test/dq_machinery_audit_pin
	parent_type = /datum/unit_test/dq_conversion_pin
	capture_roots = list(/obj/item/camera_assembly, /obj/item/supply_beacon, /obj/machinery/button/doorbell, /obj/machinery/camera, /obj/machinery/clonepod, /obj/machinery/cryopod, /obj/machinery/feeder, /obj/machinery/food_replicator, /obj/machinery/iv_drip, /obj/machinery/organ_printer/flesh, /obj/machinery/oxygen_pump, /obj/machinery/power/breakerbox, /obj/machinery/suit_storage_unit, /obj/machinery/vr_sleeper, /obj/machinery/washing_machine, /obj/structure/AIcore, /obj/machinery/computer/teleporter, /obj/machinery/syndicate_beacon, /obj/machinery/computer/med_data, /obj/machinery/computer/secure_data, /obj/machinery/computer/skills)

/datum/unit_test/dq_machinery_audit_pin/i7

/datum/unit_test/dq_machinery_audit_pin/i7/snapshot_directory()
	return "code/modules/unit_tests/snapshots/i7_bulk/"

/datum/unit_test/dq_machinery_audit_pin/i7/snapshot_name()
	return "i7_bulk"
