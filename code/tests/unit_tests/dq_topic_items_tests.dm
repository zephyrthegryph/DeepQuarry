// Item windows' links (their hrefs) through the input inbox: blueprints, the wire reader and the RCD's access page work only for someone holding the
// item. These read the same for an op.

/// A person with a screen: the tgui state an href is checked against closes for a mind-less mob, and a test mob has no client.
/mob/living/carbon/human/dq_topic_user

/mob/living/carbon/human/dq_topic_user/shared_tgui_interaction(src_object)
	return STATUS_INTERACTIVE

/datum/unit_test/dq_topic_blueprints_legend

/datum/unit_test/dq_topic_blueprints_legend/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/holder = allocate(/mob/living/carbon/human/dq_topic_user, T)
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human/dq_topic_user)
	var/obj/item/areaeditor/blueprints/plans = allocate(/obj/item/areaeditor/blueprints, T)
	plans.wire_schematics = TRUE
	holder.put_in_active_hand(plans)
	TEST_ASSERT_EQUAL(holder.get_active_hand(), plans, "the blueprints are in the holder's active hand")
	// the wire legend page opens, names a wire set and closes again
	inbox_topic(holder, plans, list("view_legend" = 1))
	TEST_ASSERT_EQUAL(plans.legend, TRUE, "the legend link opens the wire legend")
	inbox_topic(holder, plans, list("view_wireset" = "Airlock"))
	TEST_ASSERT_EQUAL(plans.legend, "Airlock", "a wire set link names the set to show")
	inbox_topic(holder, plans, list("exit_legend" = 1))
	TEST_ASSERT_EQUAL(plans.legend, FALSE, "the back link leaves the legend")
	// no schematics, no legend, however the link is forged
	plans.wire_schematics = FALSE
	inbox_topic(holder, plans, list("view_legend" = 1))
	TEST_ASSERT_EQUAL(plans.legend, FALSE, "blueprints with no wire schematics refuse the legend link")
	// a stranger (not holding them) cannot drive the page
	plans.wire_schematics = TRUE
	inbox_topic(stranger, plans, list("view_legend" = 1))
	TEST_ASSERT_EQUAL(plans.legend, FALSE, "someone not holding the blueprints cannot open their legend")
	// put down, the blueprints are no longer in the active hand
	holder.drop_item()
	inbox_topic(holder, plans, list("view_legend" = 1))
	TEST_ASSERT_EQUAL(plans.legend, FALSE, "blueprints no longer held do nothing")

/datum/unit_test/dq_topic_wire_reader_legend

/datum/unit_test/dq_topic_wire_reader_legend/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/reader_user = allocate(/mob/living/carbon/human/dq_topic_user, T)
	var/obj/item/wire_reader/reader = allocate(/obj/item/wire_reader, T)
	reader_user.put_in_active_hand(reader)
	inbox_topic(reader_user, reader, list("view_wireset" = "Airlock"))
	TEST_ASSERT_EQUAL(reader.legend, "Airlock", "the wire reader's set link names the set to show")
	inbox_topic(reader_user, reader, list("view_legend" = 1))
	TEST_ASSERT_EQUAL(reader.legend, TRUE, "its legend link goes back to the legend")

/datum/unit_test/dq_topic_rcd_access

/datum/unit_test/dq_topic_rcd_access/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/builder = allocate(/mob/living/carbon/human/dq_topic_user, T)
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human/dq_topic_user)
	var/obj/item/rcd/tool = allocate(/obj/item/rcd, T)
	builder.put_in_active_hand(tool)
	var/before = tool.use_one_access
	inbox_topic(builder, tool, list("access" = "one"))
	TEST_ASSERT(tool.use_one_access != before, "the 'one' link flips the any-one-access rule")
	inbox_topic(builder, tool, list("access" = "17"))
	TEST_ASSERT(17 in tool.conf_access, "a number link toggles that access on")
	inbox_topic(builder, tool, list("access" = "17"))
	TEST_ASSERT(!(17 in tool.conf_access), "and off again")
	inbox_topic(builder, tool, list("access" = "17"))
	inbox_topic(builder, tool, list("access" = "all"))
	TEST_ASSERT_NULL(tool.conf_access, "the 'all' link clears the list")
	// a stranger out of reach changes nothing
	before = tool.use_one_access
	inbox_topic(stranger, tool, list("access" = "one"))
	TEST_ASSERT_EQUAL(tool.use_one_access, before, "a stranger's link does nothing")

/// The GPS window names the other signals by handle: starting a track, colouring it, showing its label and stopping it work from those names, a
/// name that is made up does nothing, and the window is held through the real inventory state (open while carried, closed once put down).
/datum/unit_test/dq_topic_gps_window

/datum/unit_test/dq_topic_gps_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/obj/item/gps/mine = allocate(/obj/item/gps/on, T)
	var/obj/item/gps/other = allocate(/obj/item/gps/on, T)
	other.set_gps_tag("OTHR")
	TEST_ASSERT(user.put_in_hands(mine), "the GPS is carried")
	var/token = ref_token(other)
	var/list/data = hc_data(mine, user)
	var/list/row
	for(var/list/signal in data["signals"])
		if(signal["gpsTag"] == "OTHR")
			row = signal
	TEST_ASSERT_NOTNULL(row, "the other signal is listed")
	TEST_ASSERT_EQUAL(row["ref"], token, "by its handle")
	own(test_ui(user, mine, "startTrack", list("ref" = "not a handle")))
	TEST_ASSERT_EQUAL(length(mine.tracking_devices), 0, "a made-up name tracks nothing")
	own(test_ui(user, mine, "startTrack", list("ref" = token)))
	TEST_ASSERT_EQUAL(mine.tracking_devices[token], "#00ffff", "the track starts in the first colour")
	TEST_ASSERT(mine.showing_tracked_names[token], "with its label shown")
	own(test_ui(user, mine, "trackColor", list("ref" = token, "color" = "#ff0000")))
	TEST_ASSERT_EQUAL(mine.tracking_devices[token], "#ff0000", "the colour button sets the colour")
	own(test_ui(user, mine, "trackLabel", list("ref" = token)))
	TEST_ASSERT(!mine.showing_tracked_names?[token], "the label button hides the label")
	own(test_ui(user, mine, "trackLabel", list("ref" = token)))
	TEST_ASSERT(mine.showing_tracked_names[token], "and shows it again")
	data = hc_data(mine, user)
	for(var/list/signal in data["signals"])
		if(signal["gpsTag"] == "OTHR")
			row = signal
	TEST_ASSERT_EQUAL(row["trackingColor"], "#ff0000", "the window shows the colour of the track")
	own(test_ui(user, mine, "stopTrack", list("ref" = token)))
	TEST_ASSERT_EQUAL(length(mine.tracking_devices), 0, "the stop button ends the track")
	TEST_ASSERT_EQUAL(mine.tgui_status(user, mine.tgui_state(user)), STATUS_INTERACTIVE, "the window stays open after a press")
	user.drop_from_inventory(mine, T)
	TEST_ASSERT_EQUAL(mine.tgui_status(user, mine.tgui_state(user)), STATUS_CLOSE, "putting the GPS down closes it")

/// The clipboard window lists its sheets by handle; the buttons work on what the clipboard holds, never on a sheet that is somewhere else.
/datum/unit_test/dq_topic_clipboard_window

/datum/unit_test/dq_topic_clipboard_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/obj/item/clipboard/clip = allocate(/obj/item/clipboard, T)
	var/obj/item/paper/sheet = allocate(/obj/item/paper, T)
	var/obj/item/paper/elsewhere = allocate(/obj/item/paper, T)
	sheet.forceMove(clip)
	rel_set(clip, nameof(/obj/item/clipboard::toppaper), sheet)
	TEST_ASSERT(user.put_in_hands(clip), "the clipboard is carried")
	var/list/data = hc_data(clip, user)
	TEST_ASSERT_EQUAL(length(data["items"]), 1, "the window lists the one sheet")
	var/list/row = data["items"][1]
	TEST_ASSERT_EQUAL(row["ref"], ref_token(sheet), "by its handle")
	TEST_ASSERT(row["is_top"], "as the top sheet")
	own(test_ui(user, clip, "remove", list("ref" = ref_token(elsewhere))))
	TEST_ASSERT_EQUAL(elsewhere.loc, T, "a sheet that is not on the clipboard is left alone")
	own(test_ui(user, clip, "remove", list("ref" = "not a handle")))
	TEST_ASSERT_EQUAL(sheet.loc, clip, "and a made-up name takes nothing off")
	TEST_ASSERT_EQUAL(clip.tgui_status(user, clip.tgui_state(user)), STATUS_INTERACTIVE, "the carrier works the window")
	own(test_ui(user, clip, "remove", list("ref" = ref_token(sheet))))
	TEST_ASSERT(sheet.loc != clip, "the remove button takes the sheet off")
	TEST_ASSERT_EQUAL(clip.tgui_status(user, clip.tgui_state(user)), STATUS_INTERACTIVE, "the window is still open after a press")

/// The folder window lists its sheets by handle and takes them out by it.
/datum/unit_test/dq_topic_folder_window

/datum/unit_test/dq_topic_folder_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/obj/item/folder/folder = allocate(/obj/item/folder, T)
	var/obj/item/paper/sheet = allocate(/obj/item/paper, T)
	var/obj/item/paper/elsewhere = allocate(/obj/item/paper, T)
	TEST_ASSERT(move_into(folder, CONTAINER_SLOT_PAGES, sheet, user), "a sheet is filed")
	TEST_ASSERT(user.put_in_hands(folder), "the folder is carried")
	var/list/data = hc_data(folder, user)
	TEST_ASSERT_EQUAL(length(data["items"]), 1, "the window lists the one sheet")
	var/list/row = data["items"][1]
	TEST_ASSERT_EQUAL(row["ref"], ref_token(sheet), "by its handle")
	TEST_ASSERT_EQUAL(row["kind"], "paper", "as a paper")
	own(test_ui(user, folder, "remove", list("ref" = ref_token(elsewhere))))
	TEST_ASSERT_EQUAL(elsewhere.loc, T, "a sheet that is not in the folder is left alone")
	own(test_ui(user, folder, "remove", list("ref" = "not a handle")))
	TEST_ASSERT_EQUAL(sheet.loc, folder, "and a made-up name takes nothing out")
	own(test_ui(user, folder, "remove", list("ref" = ref_token(sheet))))
	TEST_ASSERT(sheet.loc != folder, "the remove button takes the sheet out")

/// The cloning console sends its pods and records by handle and takes them back by it; a made-up name selects nothing.
/datum/unit_test/dq_topic_cloning_window

/datum/unit_test/dq_topic_cloning_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/obj/machinery/computer/cloning/console = allocate(/obj/machinery/computer/cloning, get_step(T, EAST))
	var/obj/machinery/clonepod/pod_a = allocate(/obj/machinery/clonepod, get_step(console, EAST))
	var/obj/machinery/clonepod/pod_b = allocate(/obj/machinery/clonepod, get_step(console, NORTH))
	console.set_grid_power(TRUE)
	console.updatemodules()
	TEST_ASSERT_EQUAL(length(console.pods), 2, "the console finds both pods")
	var/list/data = hc_data(console, user)
	var/list/tokens = list()
	for(var/list/row in data["pods"])
		tokens += row["pod"]
	TEST_ASSERT((ref_token(pod_a) in tokens) && (ref_token(pod_b) in tokens), "the window names the pods by handle")
	TEST_ASSERT_EQUAL(data["selected_pod"], ref_token(console.selected_pod), "and the selected one")
	var/obj/machinery/clonepod/other = console.selected_pod == pod_a ? pod_b : pod_a
	own(test_ui(user, console, "selectpod", list("ref" = "not a handle")))
	TEST_ASSERT(console.selected_pod != other, "a made-up name selects nothing")
	own(test_ui(user, console, "selectpod", list("ref" = ref_token(other))))
	TEST_ASSERT_EQUAL(console.selected_pod, other, "the other pod's handle selects it")
	var/obj/machinery/clonepod/stray = allocate(/obj/machinery/clonepod, get_step(T, SOUTH))
	var/selected_before = console.selected_pod
	own(test_ui(user, console, "selectpod", list("ref" = ref_token(stray))))
	TEST_ASSERT_EQUAL(console.selected_pod, selected_before, "a pod the console is not linked to cannot be selected")
	// a record is named by handle too
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/datum/transhuman/body_record/record = new
	record.init_from_mob(subject)
	record.ckey = "dq_topic_cloning" // a record with no owner is "corrupt" and thrown away when it is looked at
	rel_add(console, nameof(/obj/machinery/computer/cloning::records), record)
	data = hc_data(console, user)
	TEST_ASSERT_EQUAL(length(data["records"]), 1, "the window lists the record")
	var/list/record_row = data["records"][1]
	TEST_ASSERT_EQUAL(record_row["record"], ref_token(record), "by its handle")
	own(test_ui(user, console, "view_rec", list("ref" = record_row["record"])))
	TEST_ASSERT_EQUAL(console.active_BR, record, "the view button opens that record")
	// a record of another console is not this console's to view or clone, and a console with no records names none
	var/obj/machinery/computer/cloning/other_console = allocate(/obj/machinery/computer/cloning, get_step(T, WEST))
	other_console.set_grid_power(TRUE)
	var/mob/living/carbon/human/other_subject = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/datum/transhuman/body_record/foreign = new
	foreign.init_from_mob(other_subject)
	foreign.ckey = "dq_topic_cloning_foreign"
	rel_add(other_console, nameof(/obj/machinery/computer/cloning::records), foreign)
	var/datum/transhuman/body_record/active_before = console.active_BR
	own(test_ui(user, console, "view_rec", list("ref" = ref_token(foreign))))
	TEST_ASSERT_EQUAL(console.active_BR, active_before, "a record held by another console cannot be viewed")
	own(test_ui(user, console, "clone", list("ref" = ref_token(foreign))))
	TEST_ASSERT_EQUAL(console.active_BR, active_before, "or cloned")
	TEST_ASSERT_EQUAL(other_console.active_BR, null, "and the other console is untouched")
	var/obj/machinery/computer/cloning/empty_console = allocate(/obj/machinery/computer/cloning, get_step(T, NORTH))
	empty_console.set_grid_power(TRUE)
	own(test_ui(user, empty_console, "view_rec", list("ref" = ref_token(record))))
	TEST_ASSERT_NULL(empty_console.active_BR, "a console with no records at all names none")
	TEST_ASSERT_NULL(empty_console.record_of(ref_token(record)), "so no handle finds a record in it")
