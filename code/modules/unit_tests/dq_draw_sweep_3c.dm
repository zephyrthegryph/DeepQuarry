// The draw sweep, wave 3 C: the types that draw from tracked state instead of an update_icon() provider (folder, paper plane,
// blob, NTNet relay, fuel port, glass roulette ball, shield generator). Each test moves the state a look reads and checks the
// look, with no update_icon() call in between.

/datum/unit_test/dq_draw_sweep_3c_folder

/datum/unit_test/dq_draw_sweep_3c_folder/Run()
	var/turf/T = test_floor()
	var/obj/item/folder/folder = allocate(/obj/item/folder, T)
	var/obj/item/paper/page = allocate(/obj/item/paper, T)
	refresh_flush()
	TEST_ASSERT(!("folder_paper" in folder.look_overlays), "an empty folder shows no paper: [json_encode(folder.look_overlays)]")
	TEST_ASSERT(move_into(folder, null, page), "the page goes in the folder")
	refresh_flush()
	TEST_ASSERT(("folder_paper" in folder.look_overlays), "a folder with a page shows it by itself: [json_encode(folder.look_overlays)]")

/datum/unit_test/dq_draw_sweep_3c_paperplane

/datum/unit_test/dq_draw_sweep_3c_paperplane/Run()
	var/turf/T = test_floor()
	var/obj/item/paperplane/plane = allocate(/obj/item/paperplane, T)
	var/obj/item/stamp/stamp = allocate(/obj/item/stamp, T)
	refresh_flush()
	TEST_ASSERT(!length(plane.look_overlays), "a plain plane draws no stamps: [json_encode(plane.look_overlays)]")
	plane.internalPaper.stamped = list(stamp.type)
	plane.sync_stamps()
	refresh_flush()
	TEST_ASSERT(("paperplane_[stamp.icon_state]" in plane.look_overlays), "a stamped plane draws the stamp: [json_encode(plane.look_overlays)]")

/datum/unit_test/dq_draw_sweep_3c_blob

/datum/unit_test/dq_draw_sweep_3c_blob/Run()
	var/turf/T = test_floor()
	var/obj/structure/blob/normal/blob = allocate(/obj/structure/blob/normal, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(blob.name, "inert blob", "a blob with no overmind is inert")
	blob.set_look_title("test")
	blob.set_look_tint("#ff0000")
	refresh_flush()
	TEST_ASSERT_EQUAL(blob.name, "test", "a normal blob is named by its overmind's type")
	TEST_ASSERT_EQUAL(blob.color, "#ff0000", "and tinted by it")
	blob.update_integrity(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(blob.icon_state, "blob_damaged", "a hurt blob draws its damaged state by itself")

/datum/unit_test/dq_draw_sweep_3c_ntnet_relay

/datum/unit_test/dq_draw_sweep_3c_ntnet_relay/Run()
	var/turf/T = test_floor()
	var/obj/machinery/ntnet_relay/relay = allocate(/obj/machinery/ntnet_relay, T)
	refresh_flush()
	relay.set_enabled(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(relay.icon_state, "[initial(relay.icon_state)]_off", "a switched-off relay draws its off state by itself")
	TEST_ASSERT(!relay.noisy, "and its hum stops with the look")

/datum/unit_test/dq_draw_sweep_3c_fuel_port

/datum/unit_test/dq_draw_sweep_3c_fuel_port/Run()
	var/turf/T = test_floor()
	var/obj/structure/fuel_port/port = allocate(/obj/structure/fuel_port, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(port.icon_state, port.icon_closed, "a closed port is shut")
	port.set_opened(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(port.icon_state, port.icon_full, "an opened port with its tank shows full")
	var/obj/structure/fuel_port/empty/bare = allocate(/obj/structure/fuel_port/empty, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(bare.icon_state, bare.icon_empty, "an opened port with no tank shows empty")

/datum/unit_test/dq_draw_sweep_3c_roulette_ball

/datum/unit_test/dq_draw_sweep_3c_roulette_ball/Run()
	var/turf/T = test_floor()
	var/obj/item/roulette_ball/hollow/ball = allocate(/obj/item/roulette_ball/hollow, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(ball.icon_state, "roulette_ball_glass", "an empty glass ball")
	ball.set_holds_mob(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(ball.icon_state, "roulette_ball_glass_full", "a ball with someone in it draws full by itself")

/datum/unit_test/dq_draw_sweep_3c_shield_gen

/datum/unit_test/dq_draw_sweep_3c_shield_gen/Run()
	var/turf/T = test_floor()
	var/obj/machinery/shield_gen/gen = allocate(/obj/machinery/shield_gen, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(gen.icon_state, "generator0", "an idle generator")
	gen.set_active(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(gen.icon_state, "generator1", "an active generator draws lit by itself")

/datum/unit_test/dq_draw_sweep_3c_disposal

/datum/unit_test/dq_draw_sweep_3c_disposal/Run()
	var/turf/T = test_floor()
	var/obj/machinery/disposal/bin = allocate(/obj/machinery/disposal, T)
	refresh_flush()
	TEST_ASSERT(!("disposal-handle" in bin.look_overlays), "a bin with its handle up shows no handle: [json_encode(bin.look_overlays)]")
	bin.set_flush(TRUE)
	refresh_flush()
	TEST_ASSERT(("disposal-handle" in bin.look_overlays), "a pulled handle draws by itself: [json_encode(bin.look_overlays)]")
	bin.set_flush(FALSE)
	refresh_flush()
	TEST_ASSERT(!("disposal-handle" in bin.look_overlays), "and goes with the handle: [json_encode(bin.look_overlays)]")
