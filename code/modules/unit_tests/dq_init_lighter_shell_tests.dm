// The old zippo clear-all initializer is deliberately retained in production.
/obj/item/flame/lighter/dq_shell_probe
	available_colors = list("#123456")

/obj/item/flame/lighter/zippo/dq_shell_probe
	overlays = list("old-constructor-layer")

/datum/unit_test/dq_init_lighter_native_shell
/datum/unit_test/dq_init_lighter_native_shell/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/flame/lighter/dq_shell_probe/L = allocate(/obj/item/flame/lighter/dq_shell_probe)
	var/datum/type_trait/lighter_shell/S = lighter_shell_of(L)
	TEST_ASSERT_EQUAL(S.sampled_color, "#123456", "The real constructor samples the supplied color list")
	TEST_ASSERT(S.sampled_state in list("lighter-trans", "lighter-tall", "lighter-matte"), "The sample is one of the original three cases")
	var/expected = "overlay: [S.sampled_icon]:[S.sampled_state]:[FLOAT_PLANE]:[S.sampled_color]"
	TEST_ASSERT(expected in dq_look_pin_lines(L), "The native draw contains the actual sampled shell with its original image geometry")
	var/obj/item/flame/lighter/zippo/dq_shell_probe/Z = allocate(/obj/item/flame/lighter/zippo/dq_shell_probe)
	TEST_ASSERT(!lighter_shell_of(Z).shown, "Zippo's static policy suppresses the cheap shell")
	TEST_ASSERT(lighter_shell_of(Z).sampled_state, "Zippo still performs the inherited random sampling")
	for(var/row in dq_look_pin_lines(Z))
		TEST_ASSERT(!findtext(row, ":lighter-"), "Zippo has no cheap-shell overlay")
		TEST_ASSERT(!findtext(row, "old-constructor-layer"), "Zippo still clears unrelated initial overlays through its retained initializer")
	var/state = S.sampled_state
	var/color = S.sampled_color
	var/obj/item/flame/lighter/peer = allocate(/obj/item/flame/lighter)
	L.set_icon_state("lighteron")
	draw_now(L)
	TEST_ASSERT(expected in dq_look_pin_lines(L), "Changing flame state preserves the same sampled shell")
	L.set_icon('icons/obj/candle.dmi')
	draw_now(L)
	TEST_ASSERT(expected in dq_look_pin_lines(L), "The shell keeps its originally sampled icon even if the holder's icon changes")
	TEST_ASSERT_EQUAL(S.sampled_state, state, "Redraw does not reroll the case")
	TEST_ASSERT_EQUAL(S.sampled_color, color, "Redraw does not reroll its tint")
	TEST_ASSERT(lighter_shell_of(peer) != S, "Each real constructor retains its own appearance sample")
