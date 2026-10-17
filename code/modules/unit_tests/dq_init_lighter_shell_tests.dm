// Master rolls the cheap lighter's appearance once; draw reads the live icon.
/obj/item/flame/lighter/dq_shell_probe
	available_colors = list("#123456")

/obj/item/flame/lighter/zippo/dq_shell_probe

/obj/item/flame/lighter/zippo/dq_shell_probe/draw(datum/look/look)
	..()
	look.overlay("native-probe")

/datum/unit_test/dq_init_lighter_native_shell
/datum/unit_test/dq_init_lighter_native_shell/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/flame/lighter/dq_shell_probe/L = allocate(/obj/item/flame/lighter/dq_shell_probe)
	TEST_ASSERT_EQUAL(L.cheap_color, "#123456", "The real constructor samples the supplied color list")
	TEST_ASSERT(L.cheap_pattern in list("lighter-trans", "lighter-tall", "lighter-matte"), "The sample is one of the original three cases")
	var/pattern = L.cheap_pattern
	var/color = L.cheap_color
	var/expected = "overlay: [L.icon]:[pattern]:[FLOAT_PLANE]:[color]"
	draw_now(L)
	TEST_ASSERT(expected in dq_look_pin_lines(L), "Native draw contains the actual rolled pattern and color")
	var/obj/item/flame/lighter/zippo/dq_shell_probe/Z = allocate(/obj/item/flame/lighter/zippo/dq_shell_probe)
	draw_now(Z)
	TEST_ASSERT_NULL(Z.cheap_pattern, "Zippo does not roll a cheap-shell pattern")
	TEST_ASSERT_NULL(Z.cheap_color, "Zippo does not roll a cheap-shell tint")
	var/probe_found = FALSE
	for(var/row in dq_look_pin_lines(Z))
		TEST_ASSERT(!findtext(row, ":lighter-"), "Zippo has no cheap-shell overlay")
		if(findtext(row, ":native-probe:"))
			probe_found = TRUE
	TEST_ASSERT(probe_found, "Zippo native draw preserves its subtype's authored overlay")
	L.set_icon_state("lighteron")
	draw_now(L)
	TEST_ASSERT(expected in dq_look_pin_lines(L), "Changing flame state preserves the rolled shell")
	L.set_icon('icons/obj/candle.dmi')
	draw_now(L)
	var/live_expected = "overlay: [L.icon]:[pattern]:[FLOAT_PLANE]:[color]"
	TEST_ASSERT(live_expected in dq_look_pin_lines(L), "Changing the live icon redraws the same rolled shell from that icon")
	TEST_ASSERT(!(expected in dq_look_pin_lines(L)), "Redraw removes the old icon's shell rather than accumulating layers")
	TEST_ASSERT_EQUAL(L.cheap_pattern, pattern, "Redraw does not reroll the pattern")
	TEST_ASSERT_EQUAL(L.cheap_color, color, "Redraw does not reroll its tint")
	var/obj/item/flame/lighter/peer = allocate(/obj/item/flame/lighter)
	var/peer_pattern = peer.cheap_pattern
	L.set_cheap_pattern("lighter-matte")
	draw_now(L)
	TEST_ASSERT_EQUAL(peer.cheap_pattern, peer_pattern, "One lighter's appearance edit does not mutate another instance")
