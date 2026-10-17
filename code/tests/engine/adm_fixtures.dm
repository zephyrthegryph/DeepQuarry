// Fixtures for the slot admission tests (code/modules/unit_tests/dq_slot_admission_tests.dm): slots with a mixed accepts, a fits, and each replace policy.

/obj/adm_fixture
	name = "admission holder"

CAPABILITIES(/obj/adm_fixture)
	slot("adm_mixed", accepts = list(/obj/item/flashlight, /obj/item/paper, req_loose()))
	slot("adm_types", accepts = list(/obj/item/flashlight))
	slot("adm_fits", fits = req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_SIZE_CLASS))
	slot("adm_swap", capacity = 1, replace = REPLACE)
	slot("adm_best", capacity = 1, replace = REPLACE_IF_BETTER, replace_by = "w_class")
	slot("adm_papers", accepts = /obj/item/paper)
