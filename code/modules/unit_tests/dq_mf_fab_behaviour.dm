// Behaviour tests for the fabrication machines (rewrite/machines-full): the autolathe, the R&D production machines (protolathe, circuit imprinter,
// department protolathes, and the R&D base they share with the destructive analyzer) and the exosuit and prosthetics fabricators. What a person
// with tools, sheets and disks, and the window's buttons observe, written against the legacy code first. Where the legacy code had a bug the test
// pins it as it was and the commit that fixes it edits the assertion (doc/rewrite/intended_changes.md). Fixture: the structure behaviour block
// (dq_hc_struct_behaviour.dm).

// ---- adapters: today's accessors (only these bodies change with the conversion) ----

/// The maintenance panel is open.
/proc/mffab_panel_open(obj/machinery/M)
	return !!M.panel_open

/// The machine is printing (a run, or an exosuit part under way).
/proc/mffab_busy(obj/machinery/M)
	if(istype(M, /obj/machinery/autolathe))
		return !!om_busy(M)
	if(istype(M, /obj/machinery/rnd))
		var/obj/machinery/rnd/R = M
		return !!R.busy
	var/obj/machinery/mecha_part_fabricator_tg/F = M
	return !!F.being_built()

/// `user` drags the machine onto `T`: where it drops what it prints.
/proc/mffab_drag(mob/user, obj/machinery/M, turf/T)
	call(M, "choose_drop_with_actor")(user, T)

/// The designs the window offers `user` (its static data).
/proc/mffab_design_count(obj/machinery/M, mob/user)
	var/list/data = M.tgui_static_data(user)
	return length(data["designs"])

/// The designs the autolathe knows without a disk.
/proc/mffab_autolathe_known(obj/machinery/autolathe/L)
	return L.stored_research().researched_designs

/// The design ids a disk taught the autolathe.
/proc/mffab_imported(obj/machinery/autolathe/L)
	return L.imported_designs

/// The machine's own material store.
/proc/mffab_container(obj/machinery/M) as /datum/material_container
	if(istype(M, /obj/machinery/autolathe))
		var/obj/machinery/autolathe/L = M
		return L.materials
	if(istype(M, /obj/machinery/rnd/production))
		var/obj/machinery/rnd/production/P = M
		return P.materials.mat_container()
	var/obj/machinery/mecha_part_fabricator_tg/F = M
	return F.rmat.mat_container()

/// The exosuit fabricator starts the first part of its queue. (The legacy one steps on a machine lane the test clock does not drive, and times a part
/// by world.time: its step is run by hand.)
/proc/mffab_exofab_start(obj/machinery/mecha_part_fabricator_tg/F)
	F.machine_step()

/// The exosuit fabricator works until it has nothing left to do: every part made, each dropped or held for a blocked exit.
/proc/mffab_exofab_run(obj/machinery/mecha_part_fabricator_tg/F)
	for(var/i in 1 to 20)
		if(F.being_built())
			EXPIRY_SET(F, build_finish, -1, CLOCK_WORLD)
		F.machine_step()

/// A window `user` keeps open on the machine while it asks something (a legacy question belongs to its window).
/proc/mffab_open_window(mob/user, obj/machinery/M)
	var/datum/tgui/ui = new(user, M, "HcTest")
	ui.status = STATUS_INTERACTIVE
	return ui

/// A button pressed in that window.
/proc/mffab_window_press(mob/user, obj/machinery/M, datum/tgui/ui, action, list/args)
	return M.tgui_act(action, args || list(), ui)

/proc/mffab_close_window(datum/tgui/ui)
	qdel(ui)

/// What examining the machine tells `user`, as one text.
/proc/mffab_examine(obj/machinery/M, mob/user)
	return jointext(M.examine(user), " ")

// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/mffab
	abstract_type = /datum/unit_test/dq_hc_struct/mffab

/// A tool of `path` that works at once, in the person's active hand.
/datum/unit_test/dq_hc_struct/mffab/proc/in_hand(mob/living/carbon/human/H, path)
	var/obj/item/W = dq_fast_tool(path, get_turf(H))
	if(H.get_active_hand())
		H.drop_item()
	H.put_in_active_hand(W)
	return W

/// A click as a player makes it, and time passes.
/datum/unit_test/dq_hc_struct/mffab/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	hci_click(H, target, held)
	settle()

/// Long enough for any print run of a few items to finish.
/datum/unit_test/dq_hc_struct/mffab/proc/long_settle()
	test_time(5 MINUTES)

/// How many `path` lie on `T`.
/datum/unit_test/dq_hc_struct/mffab/proc/count_on(turf/T, path)
	. = 0
	for(var/atom/movable/AM in T)
		if(istype(AM, path))
			.++

/// A plain design of `build_type`: made of materials only, no material choice, not a stack, not hacked-only; among `ids`
/// (every design when null), the quickest to make (ties by id). `skip` names one not to pick.
/datum/unit_test/dq_hc_struct/mffab/proc/plain_design(build_type, list/ids, datum/design_techweb/skip)
	var/datum/design_techweb/best
	var/list/candidates = ids || SSresearch.techweb_designs
	for(var/id in candidates)
		var/datum/design_techweb/D = SSresearch.techweb_design_by_id(id)
		if(!D || D == skip || !(D.build_type & build_type) || D.material_template || D.make_reagent || length(D.reagents_list) || !length(D.materials))
			continue
		if(!ispath(D.build_path, /obj/item) || ispath(D.build_path, /obj/item/stack) || (RND_CATEGORY_HACKED in D.category))
			continue
		if(!best || D.construction_time < best.construction_time || (D.construction_time == best.construction_time && sorttext(D.id, best.id) > 0))
			best = D
	return best

/// Loads the machine with `times` the materials of `D`.
/datum/unit_test/dq_hc_struct/mffab/proc/stock(obj/machinery/M, datum/design_techweb/D, times = 10)
	var/datum/material_container/C = mffab_container(M)
	for(var/id in D.materials)
		var/datum/material/mat = istype(id, /datum/material) ? id : get_material_by_name(id)
		C.insert_amount_mat(D.materials[id] * times, mat)

/// A techweb of its own that knows `designs`, connected to the machine.
/datum/unit_test/dq_hc_struct/mffab/proc/teach(obj/machinery/M, list/designs)
	var/datum/techweb/web = new /datum/techweb
	for(var/datum/design_techweb/D as anything in designs)
		web.add_design(D)
	call(M, "connect_techweb")(web)
	return web

// ---------------------------------------------------------------------------------------------------------------------
// The autolathe
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/mffab/proc/lathe(turf/T)
	return mach(/obj/machinery/autolathe, T || tile(3, 2))

/// A screwdriver opens the panel (and shows the wires) and closes it again.
/datum/unit_test/dq_hc_struct/mffab/lathe_screwdriver_opens_the_panel
/datum/unit_test/dq_hc_struct/mffab/lathe_screwdriver_opens_the_panel/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	var/obj/item/S = in_hand(H, /obj/item/tool/screwdriver)
	touch(H, L, S)
	TEST_ASSERT(mffab_panel_open(L), "a screwdriver opens the panel")
	TEST_ASSERT(H in wires_test(L).opened_for(), "and the wires are shown")
	touch(H, L, S)
	TEST_ASSERT(!mffab_panel_open(L), "and closes it")

/// With the panel open a hand reaches the wires; with it shut wirecutters do not.
/datum/unit_test/dq_hc_struct/mffab/lathe_wires_behind_the_panel
/datum/unit_test/dq_hc_struct/mffab/lathe_wires_behind_the_panel/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	var/obj/item/C = in_hand(H, /obj/item/tool/wirecutters)
	touch(H, L, C)
	TEST_ASSERT(!(H in wires_test(L).opened_for()), "with the panel shut the cutters do not reach the wires")
	touch(H, L, in_hand(H, /obj/item/tool/screwdriver))
	var/shown = length(wires_test(L).opened_for())
	H.drop_item()
	touch(H, L, null)
	TEST_ASSERT(length(wires_test(L).opened_for()) > shown, "an open panel shows a hand the wires")

/// A crowbar takes the lathe apart into a frame with its board, only with the panel open.
/datum/unit_test/dq_hc_struct/mffab/lathe_crowbar_dismantles_behind_the_panel
/datum/unit_test/dq_hc_struct/mffab/lathe_crowbar_dismantles_behind_the_panel/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/autolathe/L = lathe(T)
	var/obj/item/bar = in_hand(H, /obj/item/tool/crowbar)
	touch(H, L, bar)
	TEST_ASSERT(!QDELETED(L), "a shut panel keeps it whole")
	touch(H, L, in_hand(H, /obj/item/tool/screwdriver))
	touch(H, L, in_hand(H, /obj/item/tool/crowbar))
	TEST_ASSERT(QDELETED(L), "an open one lets the crowbar take it apart")
	var/obj/structure/frame/F = locate() in T
	TEST_ASSERT_NOTNULL(F, "into a frame")
	TEST_ASSERT(istype(F.circuit, /obj/item/circuitboard/autolathe), "holding its board")

/// A design is printed as many times as asked, from the loaded materials, onto the lathe's tile.
/datum/unit_test/dq_hc_struct/mffab/lathe_prints_a_design
/datum/unit_test/dq_hc_struct/mffab/lathe_prints_a_design/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/autolathe/L = lathe(T)
	var/datum/design_techweb/D = plain_design(AUTOLATHE, mffab_autolathe_known(L))
	TEST_ASSERT_NOTNULL(D, "(the lathe knows a plain design)")
	stock(L, D)
	var/before = mffab_container(L).total_amount()
	hc_ui(H, L, "make", list("id" = D.id, "multiplier" = 2))
	TEST_ASSERT(mffab_busy(L), "the lathe is busy printing")
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 2, "two are printed onto its tile")
	TEST_ASSERT(mffab_container(L).total_amount() < before, "from its materials")
	TEST_ASSERT(!mffab_busy(L), "and it is free again")

/// A second run asked for while one prints is refused.
/datum/unit_test/dq_hc_struct/mffab/lathe_one_run_at_a_time
/datum/unit_test/dq_hc_struct/mffab/lathe_one_run_at_a_time/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/autolathe/L = lathe(T)
	var/datum/design_techweb/D = plain_design(AUTOLATHE, mffab_autolathe_known(L))
	stock(L, D)
	hc_ui(H, L, "make", list("id" = D.id, "multiplier" = 2))
	hc_ui(H, L, "make", list("id" = D.id, "multiplier" = 2))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 2, "only the first run prints")

/// The disable wire cut, the lathe prints nothing.
/datum/unit_test/dq_hc_struct/mffab/lathe_disable_wire_stops_printing
/datum/unit_test/dq_hc_struct/mffab/lathe_disable_wire_stops_printing/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/autolathe/L = lathe(T)
	var/datum/design_techweb/D = plain_design(AUTOLATHE, mffab_autolathe_known(L))
	stock(L, D)
	wires_test(L).cut(WIRE_LATHE_DISABLE, H)
	press(H, L, "make", list("id" = D.id, "multiplier" = 1))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 0, "nothing is printed")

/// Not enough materials: nothing is printed and nothing is spent.
/datum/unit_test/dq_hc_struct/mffab/lathe_needs_its_materials
/datum/unit_test/dq_hc_struct/mffab/lathe_needs_its_materials/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/autolathe/L = lathe(T)
	var/datum/design_techweb/D = plain_design(AUTOLATHE, mffab_autolathe_known(L))
	stock(L, D, 1)
	var/before = mffab_container(L).total_amount()
	press(H, L, "make", list("id" = D.id, "multiplier" = 5))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 0, "nothing is printed")
	TEST_ASSERT_EQUAL(mffab_container(L).total_amount(), before, "and nothing is spent")

/// Dragged onto a tile, the lathe drops what it prints there; onto a blocked tile it drops on its own; alt-click forgets the direction.
/datum/unit_test/dq_hc_struct/mffab/lathe_drop_direction
/datum/unit_test/dq_hc_struct/mffab/lathe_drop_direction/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/turf/east = get_step(T, EAST)
	var/obj/machinery/autolathe/L = lathe(T)
	var/datum/design_techweb/D = plain_design(AUTOLATHE, mffab_autolathe_known(L))
	stock(L, D)
	mffab_drag(H, L, east)
	TEST_ASSERT_EQUAL(L.drop_direction, EAST, "dragged east, it drops east")
	press(H, L, "make", list("id" = D.id, "multiplier" = 1))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(east, D.build_path), 1, "the print lands on the east tile")
	var/was_dense = east.density
	east.set_density(TRUE)
	press(H, L, "make", list("id" = D.id, "multiplier" = 1))
	long_settle()
	east.set_density(was_dense)
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 1, "a blocked tile sends it onto the lathe's own")
	test_click(H, L, null, GESTURE_ALT)
	settle()
	TEST_ASSERT_EQUAL(L.drop_direction, 0, "alt-click forgets the direction")

/// While it prints, the direction cannot be changed.
/datum/unit_test/dq_hc_struct/mffab/lathe_keeps_its_direction_while_printing
/datum/unit_test/dq_hc_struct/mffab/lathe_keeps_its_direction_while_printing/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/autolathe/L = lathe(T)
	var/datum/design_techweb/D = plain_design(AUTOLATHE, mffab_autolathe_known(L))
	stock(L, D)
	hc_ui(H, L, "make", list("id" = D.id, "multiplier" = 3))
	TEST_ASSERT(mffab_busy(L), "(printing)")
	mffab_drag(H, L, get_step(T, EAST))
	TEST_ASSERT_EQUAL(L.drop_direction, 0, "a drag while printing changes nothing")
	long_settle()

/// A design disk teaches the lathe the designs it can make; others are left out.
/datum/unit_test/dq_hc_struct/mffab/lathe_learns_from_a_disk
/datum/unit_test/dq_hc_struct/mffab/lathe_learns_from_a_disk/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	var/list/known = mffab_autolathe_known(L)
	var/datum/design_techweb/fits
	var/datum/design_techweb/other
	for(var/id in SSresearch.techweb_designs)
		var/datum/design_techweb/D = SSresearch.techweb_design_by_id(id)
		if(!D || (id in known))
			continue
		if(!fits && (D.build_type & AUTOLATHE))
			fits = D
		else if(!other && !(D.build_type & AUTOLATHE))
			other = D
	TEST_ASSERT(fits && other, "(a design the lathe can learn and one it cannot)")
	var/obj/item/disk/design_disk/disk = allocate(/obj/item/disk/design_disk, get_turf(H))
	LAZYADD(disk.blueprints, fits)
	LAZYADD(disk.blueprints, other)
	H.put_in_active_hand(disk)
	touch(H, L, disk)
	TEST_ASSERT(LAZYACCESS(mffab_imported(L), fits.id), "the lathe learns the design it can make")
	TEST_ASSERT(!LAZYACCESS(mffab_imported(L), other.id), "and not the other")

/// With the panel open, a disk teaches it nothing.
/datum/unit_test/dq_hc_struct/mffab/lathe_open_panel_takes_no_disk
/datum/unit_test/dq_hc_struct/mffab/lathe_open_panel_takes_no_disk/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	var/datum/design_techweb/fits
	for(var/id in SSresearch.techweb_designs)
		var/datum/design_techweb/D = SSresearch.techweb_design_by_id(id)
		if(D && (D.build_type & AUTOLATHE) && !(id in mffab_autolathe_known(L)))
			fits = D
			break
	touch(H, L, in_hand(H, /obj/item/tool/screwdriver))
	var/obj/item/disk/design_disk/disk = allocate(/obj/item/disk/design_disk, get_turf(H))
	LAZYADD(disk.blueprints, fits)
	H.drop_item()
	H.put_in_active_hand(disk)
	touch(H, L, disk)
	TEST_ASSERT(!LAZYACCESS(mffab_imported(L), fits.id), "an open panel learns nothing")

/// The hack wire cut shows the hacked designs too.
/datum/unit_test/dq_hc_struct/mffab/lathe_hack_shows_more_designs
/datum/unit_test/dq_hc_struct/mffab/lathe_hack_shows_more_designs/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	var/before = mffab_design_count(L, H)
	wires_test(L).cut(WIRE_LATHE_HACK, H)
	TEST_ASSERT(mffab_design_count(L, H) > before, "hacked, it offers more designs")
	wires_test(L).cut(WIRE_LATHE_HACK, H)
	TEST_ASSERT_EQUAL(mffab_design_count(L, H), before, "mended, the same as before")

/// Sheets used on the lathe go into its materials.
/datum/unit_test/dq_hc_struct/mffab/lathe_takes_sheets
/datum/unit_test/dq_hc_struct/mffab/lathe_takes_sheets/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, get_turf(H))
	S.set_amount(5)
	H.put_in_active_hand(S)
	touch(H, L, S)
	TEST_ASSERT(mffab_container(L).total_amount() > 0, "the sheets are loaded")
	TEST_ASSERT(QDELETED(S) || S.get_amount() < 5, "and leave the hand")

/// Examined up close, the lathe says what its materials cost.
/datum/unit_test/dq_hc_struct/mffab/lathe_examine
/datum/unit_test/dq_hc_struct/mffab/lathe_examine/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/autolathe/L = lathe()
	TEST_ASSERT(findtext(mffab_examine(L, H), "Material usage cost"), "the material cost is shown")

// ---------------------------------------------------------------------------------------------------------------------
// The R&D production machines (and the R&D base)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/mffab/proc/protolathe(type = /obj/machinery/rnd/production/protolathe, turf/T)
	return mach(type, T || tile(3, 2))

/// A screwdriver opens the panel and shows the wires; an open panel shows a hand the wires.
/datum/unit_test/dq_hc_struct/mffab/protolathe_panel_and_wires
/datum/unit_test/dq_hc_struct/mffab/protolathe_panel_and_wires/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/rnd/production/protolathe/P = protolathe()
	touch(H, P, in_hand(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(mffab_panel_open(P), "a screwdriver opens the panel")
	TEST_ASSERT(H in wires_test(P).opened_for(), "and shows the wires")
	var/shown = length(wires_test(P).opened_for())
	H.drop_item()
	touch(H, P, null)
	TEST_ASSERT(length(wires_test(P).opened_for()) > shown, "a hand at the open panel reaches the wires")

/// A wrench frees it and bolts it down again, only with the panel shut.
/datum/unit_test/dq_hc_struct/mffab/protolathe_wrench_moves_it
/datum/unit_test/dq_hc_struct/mffab/protolathe_wrench_moves_it/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/rnd/production/protolathe/P = protolathe()
	var/obj/item/W = in_hand(H, /obj/item/tool/wrench)
	touch(H, P, W)
	TEST_ASSERT(!P.anchored, "a wrench frees it")
	touch(H, P, W)
	TEST_ASSERT(P.anchored, "and bolts it down")
	touch(H, P, in_hand(H, /obj/item/tool/screwdriver))
	touch(H, P, in_hand(H, /obj/item/tool/wrench))
	TEST_ASSERT(P.anchored, "not with the panel open")

/// A crowbar takes it apart into a frame with its board, only with the panel open.
/datum/unit_test/dq_hc_struct/mffab/protolathe_crowbar_dismantles
/datum/unit_test/dq_hc_struct/mffab/protolathe_crowbar_dismantles/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/rnd/production/protolathe/P = protolathe(T = T)
	touch(H, P, in_hand(H, /obj/item/tool/crowbar))
	TEST_ASSERT(!QDELETED(P), "a shut panel keeps it whole")
	touch(H, P, in_hand(H, /obj/item/tool/screwdriver))
	touch(H, P, in_hand(H, /obj/item/tool/crowbar))
	TEST_ASSERT(QDELETED(P), "an open one lets the crowbar take it apart")
	var/obj/structure/frame/F = locate() in T
	TEST_ASSERT(F && istype(F.circuit, /obj/item/circuitboard/machine/protolathe), "into a frame holding its board")

/// A researched design is built as many times as asked onto its tile.
/datum/unit_test/dq_hc_struct/mffab/protolathe_builds_a_design
/datum/unit_test/dq_hc_struct/mffab/protolathe_builds_a_design/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/rnd/production/protolathe/P = protolathe(T = T)
	var/datum/design_techweb/D = plain_design(PROTOLATHE)
	TEST_ASSERT_NOTNULL(D, "(a plain protolathe design)")
	teach(P, list(D))
	stock(P, D)
	var/before = mffab_container(P).total_amount()
	hc_ui(H, P, "build", list("ref" = D.id, "amount" = 2))
	TEST_ASSERT(mffab_busy(P), "it is busy building")
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 2, "two are built onto its tile")
	TEST_ASSERT(mffab_container(P).total_amount() < before, "from its materials")
	TEST_ASSERT(!mffab_busy(P), "and it is free again")

/// A design it has no manipulators for is refused.
/datum/unit_test/dq_hc_struct/mffab/protolathe_refuses_other_machines_designs
/datum/unit_test/dq_hc_struct/mffab/protolathe_refuses_other_machines_designs/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/rnd/production/protolathe/P = protolathe(T = T)
	var/datum/design_techweb/D
	for(var/id in SSresearch.techweb_designs)
		var/datum/design_techweb/candidate = SSresearch.techweb_design_by_id(id)
		if(candidate && candidate.build_type && !(candidate.build_type & PROTOLATHE) && length(candidate.materials) && ispath(candidate.build_path, /obj/item) && !candidate.material_template)
			D = candidate
			break
	teach(P, list(D))
	stock(P, D)
	press(H, P, "build", list("ref" = D.id, "amount" = 1))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 0, "nothing is built")

/// A second build asked for while one runs is refused.
/datum/unit_test/dq_hc_struct/mffab/protolathe_one_run_at_a_time
/datum/unit_test/dq_hc_struct/mffab/protolathe_one_run_at_a_time/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/rnd/production/protolathe/P = protolathe(T = T)
	var/datum/design_techweb/D = plain_design(PROTOLATHE)
	teach(P, list(D))
	stock(P, D)
	hc_ui(H, P, "build", list("ref" = D.id, "amount" = 2))
	hc_ui(H, P, "build", list("ref" = D.id, "amount" = 2))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 2, "only the first run builds")

/// Its drop direction: onto a blocked floor that is not a wall the legacy lathe still drops there (the autolathe drops on its own tile).
/datum/unit_test/dq_hc_struct/mffab/protolathe_drop_direction
/datum/unit_test/dq_hc_struct/mffab/protolathe_drop_direction/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/turf/east = get_step(T, EAST)
	var/obj/machinery/rnd/production/protolathe/P = protolathe(T = T)
	var/datum/design_techweb/D = plain_design(PROTOLATHE)
	teach(P, list(D))
	stock(P, D)
	mffab_drag(H, P, east)
	TEST_ASSERT_EQUAL(P.drop_direction, EAST, "dragged east, it drops east")
	press(H, P, "build", list("ref" = D.id, "amount" = 1))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(east, D.build_path), 1, "the build lands on the east tile")
	var/was_dense = east.density
	east.set_density(TRUE)
	press(H, P, "build", list("ref" = D.id, "amount" = 1))
	long_settle()
	east.set_density(was_dense)
	TEST_ASSERT_EQUAL(count_on(east, D.build_path), 2, "a blocked floor still takes it (legacy)")

/// Sheets come back out of its materials on request.
/datum/unit_test/dq_hc_struct/mffab/protolathe_ejects_sheets
/datum/unit_test/dq_hc_struct/mffab/protolathe_ejects_sheets/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/rnd/production/protolathe/P = protolathe(T = T)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	mffab_container(P).insert_amount_mat(SHEET_MATERIAL_AMOUNT * 5, steel)
	press(H, P, "remove_mat", list("id" = MAT_STEEL, "amount" = 2))
	TEST_ASSERT_EQUAL(mffab_container(P).get_material_amount(steel), SHEET_MATERIAL_AMOUNT * 3, "two sheets' worth leave the store")
	var/obj/item/stack/material/steel/S = locate() in T
	TEST_ASSERT(S && S.get_amount() == 2, "as two sheets on its tile")

/// The circuit imprinter builds its own designs.
/datum/unit_test/dq_hc_struct/mffab/imprinter_builds_a_board
/datum/unit_test/dq_hc_struct/mffab/imprinter_builds_a_board/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/rnd/production/circuit_imprinter/C = protolathe(/obj/machinery/rnd/production/circuit_imprinter, T)
	var/datum/design_techweb/D = plain_design(IMPRINTER)
	TEST_ASSERT_NOTNULL(D, "(a plain imprinter design)")
	teach(C, list(D))
	stock(C, D)
	press(H, C, "build", list("ref" = D.id, "amount" = 1))
	long_settle()
	TEST_ASSERT_EQUAL(count_on(T, D.build_path), 1, "it is built")

/// The destructive analyzer shares the R&D base: a screwdriver opens its panel and shows the wires.
/datum/unit_test/dq_hc_struct/mffab/analyzer_panel_and_wires
/datum/unit_test/dq_hc_struct/mffab/analyzer_panel_and_wires/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/rnd/A = mach(/obj/machinery/rnd/destructive_analyzer, tile(3, 2))
	touch(H, A, in_hand(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(mffab_panel_open(A), "a screwdriver opens the panel")
	TEST_ASSERT(H in wires_test(A).opened_for(), "and shows the wires")

// ---------------------------------------------------------------------------------------------------------------------
// The exosuit and prosthetics fabricators
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/mffab/proc/exofab(type = /obj/machinery/mecha_part_fabricator_tg, turf/T)
	return mach(type, T || tile(3, 3))

/// The queue is built in order and each part drops out of its exit (south by default).
/datum/unit_test/dq_hc_struct/mffab/exofab_builds_its_queue
/datum/unit_test/dq_hc_struct/mffab/exofab_builds_its_queue/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 3)
	var/obj/machinery/mecha_part_fabricator_tg/F = exofab(T = T)
	var/datum/design_techweb/D = plain_design(MECHFAB)
	TEST_ASSERT_NOTNULL(D, "(a plain exosuit design)")
	teach(F, list(D))
	stock(F, D)
	hc_ui(H, F, "build", list("designs" = list(D.id, D.id), "now" = TRUE))
	mffab_exofab_run(F)
	TEST_ASSERT_EQUAL(count_on(get_step(T, SOUTH), D.build_path), 2, "both parts drop out of the exit")
	TEST_ASSERT(!mffab_busy(F), "and it is idle again")

/// An exit blocked while a part is made holds the part until it clears.
/datum/unit_test/dq_hc_struct/mffab/exofab_holds_a_part_for_a_blocked_exit
/datum/unit_test/dq_hc_struct/mffab/exofab_holds_a_part_for_a_blocked_exit/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 3)
	var/turf/exit = get_step(T, SOUTH)
	var/obj/machinery/mecha_part_fabricator_tg/F = exofab(T = T)
	var/datum/design_techweb/D = plain_design(MECHFAB)
	teach(F, list(D))
	stock(F, D)
	hc_ui(H, F, "build", list("designs" = list(D.id), "now" = TRUE))
	mffab_exofab_start(F)
	TEST_ASSERT(mffab_busy(F), "(a part is being made)")
	var/was_dense = exit.density
	exit.set_density(TRUE)
	mffab_exofab_run(F)
	TEST_ASSERT_EQUAL(count_on(exit, D.build_path), 0, "a blocked exit gets nothing")
	exit.set_density(was_dense)
	mffab_exofab_run(F)
	TEST_ASSERT_EQUAL(count_on(exit, D.build_path), 1, "the part comes out once it clears")

/// The queue's buttons: add without starting, take one out, clear it, start and stop it.
/datum/unit_test/dq_hc_struct/mffab/exofab_queue_controls
/datum/unit_test/dq_hc_struct/mffab/exofab_queue_controls/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/mecha_part_fabricator_tg/F = exofab()
	var/datum/design_techweb/D = plain_design(MECHFAB)
	teach(F, list(D))
	press(H, F, "build", list("designs" = list(D.id, D.id), "now" = FALSE))
	TEST_ASSERT_EQUAL(length(F.queue), 2, "two are queued")
	TEST_ASSERT(!mffab_busy(F), "without starting")
	press(H, F, "del_queue_part", list("index" = 1))
	TEST_ASSERT_EQUAL(length(F.queue), 1, "one is taken out")
	press(H, F, "clear_queue")
	TEST_ASSERT_EQUAL(length(F.queue), 0, "the queue is cleared")
	press(H, F, "build", list("designs" = list(D.id), "now" = FALSE))
	press(H, F, "build_queue")
	TEST_ASSERT(F.process_queue, "build_queue starts it")
	press(H, F, "stop_queue")
	TEST_ASSERT(!F.process_queue, "stop_queue stops it")

/// Sheets come back out of its materials on request.
/datum/unit_test/dq_hc_struct/mffab/exofab_ejects_sheets
/datum/unit_test/dq_hc_struct/mffab/exofab_ejects_sheets/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 3)
	var/obj/machinery/mecha_part_fabricator_tg/F = exofab(T = T)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	mffab_container(F).insert_amount_mat(SHEET_MATERIAL_AMOUNT * 5, steel)
	press(H, F, "remove_mat", list("id" = MAT_STEEL, "amount" = 2))
	TEST_ASSERT_EQUAL(mffab_container(F).get_material_amount(steel), SHEET_MATERIAL_AMOUNT * 3, "two sheets' worth leave the store")

/// Its drop direction follows a drag, but not while a part is made.
/datum/unit_test/dq_hc_struct/mffab/exofab_drop_direction
/datum/unit_test/dq_hc_struct/mffab/exofab_drop_direction/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 3)
	var/obj/machinery/mecha_part_fabricator_tg/F = exofab(T = T)
	mffab_drag(H, F, get_step(T, EAST))
	TEST_ASSERT_EQUAL(F.drop_direction, EAST, "dragged east, it drops east")
	var/datum/design_techweb/D = plain_design(MECHFAB)
	teach(F, list(D))
	stock(F, D)
	hc_ui(H, F, "build", list("designs" = list(D.id), "now" = TRUE))
	mffab_exofab_start(F)
	mffab_drag(H, F, get_step(T, NORTH))
	TEST_ASSERT_EQUAL(F.drop_direction, EAST, "not while a part is made")
	mffab_exofab_run(F)
	TEST_ASSERT_EQUAL(count_on(get_step(T, EAST), D.build_path), 1, "the part drops east")

/// The legacy exosuit fabricator has no maintenance panel: a screwdriver does nothing.
/datum/unit_test/dq_hc_struct/mffab/exofab_panel
/datum/unit_test/dq_hc_struct/mffab/exofab_panel/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/mecha_part_fabricator_tg/F = exofab()
	touch(H, F, in_hand(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(!mffab_panel_open(F), "no panel opens (legacy)")

/// The prosthetics fabricator asks which manufacturer to build for.
/datum/unit_test/dq_hc_struct/mffab/prosfab_manufacturer
/datum/unit_test/dq_hc_struct/mffab/prosfab_manufacturer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/mecha_part_fabricator_tg/prosthetics/F = exofab(/obj/machinery/mecha_part_fabricator_tg/prosthetics)
	var/wanted
	for(var/company in GLOB.all_robolimbs)
		var/datum/robolimb/R = GLOB.all_robolimbs[company]
		if(!R.unavailable_to_build && !("Human" in R.species_cannot_use))
			wanted = company
			break
	TEST_ASSERT_NOTNULL(wanted, "(a manufacturer to pick)")
	var/datum/tgui/window = mffab_open_window(H, F)
	mffab_window_press(H, F, window, "manufacturer")
	TEST_ASSERT(asked(H), "the manufacturer is asked for")
	hci_answer(H, wanted)
	settle()
	mffab_close_window(window)
