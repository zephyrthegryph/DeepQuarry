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

MSG_DEF_SELF(adm/dress_yourself, "Only its wearer may put it on.")

/// A hat whose own /datum/act/equip rule reads the actor: only the wearer may put it on (the item holds the hook, the wearer is the target).
/obj/item/clothing/head/soft/adm_fixture

CAPABILITIES(/obj/item/clothing/head/soft/adm_fixture)
	extend(/datum/act/equip, needs(req(PROC_REF(dressed_by_wearer))))

/obj/item/clothing/head/soft/adm_fixture/proc/dressed_by_wearer(datum/act/op/A)
	return A.actor == A.target ? null : MSG(adm/dress_yourself)
