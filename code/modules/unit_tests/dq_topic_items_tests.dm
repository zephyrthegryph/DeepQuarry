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
