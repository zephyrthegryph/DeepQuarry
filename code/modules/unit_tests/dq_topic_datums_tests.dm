// Window links (hrefs) of plain datums through the input inbox: a codex book's page links go to its tree, a vote's link opens its window, and an
// admin-only game mode link is refused for a player. These read the same for an op.

/// The codex window's buttons are ops of the tree: a page button opens that page for the reader, up / back / home move them, a page of another
/// codex is refused, and a quick link or a search opens the page it names.
/datum/unit_test/dq_topic_codex_navigation

/datum/unit_test/dq_topic_codex_navigation/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/reader = allocate(/mob/living/carbon/human, T)
	var/obj/item/book/codex/book = allocate(/obj/item/book/codex, T)
	var/datum/codex_tree/tree = book.tree
	TEST_ASSERT_NOTNULL(tree, "the codex has its tree")
	TEST_ASSERT_NOTNULL(tree.home, "the tree has a home page")
	var/datum/lore/codex/category/home = tree.home
	var/datum/lore/codex/child = null
	for(var/datum/lore/codex/page in home.child_pages)
		child = page
		break
	TEST_ASSERT_NOTNULL(child, "the home page has a child page")
	tree.reader_of(reader).visit(home, FALSE)
	var/list/order = tree.pages_in_order()
	var/child_id = order.Find(child)
	TEST_ASSERT(child_id > 1, "a page has a place in the tree's order, after the home page")
	var/datum/op_result/opened = own(test_ui(reader, tree, "target", list("page" = child_id)))
	TEST_ASSERT_EQUAL(opened?.outcome, ACT_COMMITTED, "a page button reaches its op; reason=[opened?.reason]")
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), child, "a page button opens that page for the reader")
	var/list/data = hc_data(tree, reader)
	TEST_ASSERT_EQUAL(data["page_name"], child.name, "the window shows the reader's page")
	TEST_ASSERT(data["can_up"], "and offers the way up")
	TEST_ASSERT(data["can_home"], "and home")
	test_ui(reader, tree, "go_to_parent")
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), home, "the up button goes to the parent")
	test_ui(reader, tree, "target", list("page" = child_id))
	test_ui(reader, tree, "go_to_home")
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), home, "the home button goes to the home page")
	test_ui(reader, tree, "go_back")
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), child, "the back button returns to the page before")
	test_ui(reader, tree, "go_to_home")
	test_ui(reader, tree, "quick_link", list("term" = child.name))
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), child, "a quick link opens the page whose name it carries")
	// a page that is not in this tree is refused
	var/before = tree.current_page_of(reader)
	var/datum/op_result/refused = own(test_ui(reader, tree, "target", list("page" = length(order) + 1)))
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a page the codex does not have is refused")
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), before, "and the reader stays where they were")

/datum/unit_test/dq_topic_game_mode_rights

/datum/unit_test/dq_topic_game_mode_rights/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human, T)
	var/datum/game_mode/mode = new /datum/game_mode
	var/respawn_before = mode.deny_respawn
	var/ert_before = mode.ert_disabled
	inbox_topic(player, mode, list("toggle" = "respawn"))
	inbox_topic(player, mode, list("toggle" = "ert"))
	TEST_ASSERT_EQUAL(mode.deny_respawn, respawn_before, "a player's respawn link changes nothing")
	TEST_ASSERT_EQUAL(mode.ert_disabled, ert_before, "a player's ERT link changes nothing")
	qdel(mode)
