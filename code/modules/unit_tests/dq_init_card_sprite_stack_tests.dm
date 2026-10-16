// Real constructor stack identity and public runtime reset behavior.
/obj/item/card/dq_initial_stack
	initial_sprite_stack = list("base-stamp", "top-blue")
/obj/item/card/dq_initial_stack/mapped/Initialize(mapload, list/mapped_stack)
	initial_sprite_stack = mapped_stack
	return ..()

/datum/unit_test/dq_init_card_sprite_stack/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/card/dq_initial_stack/C = allocate(/obj/item/card/dq_initial_stack, test_floor())
	TEST_ASSERT_EQUAL(C.sprite_stack, C.initial_sprite_stack, "birth retains the exact original shared stack identity")
	TEST_ASSERT_EQUAL(length(C.sprite_stack), 2, "birth retains both real declared layer entries")
	var/list/mapped = list("base-stamp-gold", "top-generic", "stamp-n")
	var/obj/item/card/dq_initial_stack/mapped/M = allocate(/obj/item/card/dq_initial_stack/mapped, test_floor(), mapped)
	TEST_ASSERT_EQUAL(M.sprite_stack, mapped, "the constructor's real instance stack replaces the compiled default")
	M.set_sprite_stack(list("base-stamp-dark"))
	TEST_ASSERT_EQUAL(length(M.sprite_stack), 1, "a real runtime stack replacement remains effective")
	M.reset_icon()
	TEST_ASSERT_EQUAL(M.sprite_stack, mapped, "public reset_icon still restores that exact instance's starting stack")
	TEST_ASSERT_EQUAL(C.sprite_stack, C.initial_sprite_stack, "another card's runtime reset does not change this card")
