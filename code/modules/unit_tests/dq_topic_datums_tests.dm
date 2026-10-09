// Window links (hrefs) of plain datums through the input inbox: a codex book's page links go to its tree, a vote's link opens its window, and an
// admin-only game mode link is refused for a player. These read the same for an op.

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
	// a page's own link is forwarded to its tree: target= names a page of the tree
	inbox_topic(reader, home, list("target" = "[REF(child)]"))
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), child, "a page link opens that page for the reader")
	inbox_topic(reader, tree, list("go_to_parent" = 1))
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), home, "the up link goes to the parent")
	inbox_topic(reader, tree, list("target" = "[REF(child)]"))
	inbox_topic(reader, tree, list("go_to_home" = 1))
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), home, "the home link goes to the home page")
	inbox_topic(reader, tree, list("go_back" = 1))
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), child, "the back link returns to the page before")
	// a page of another codex is not a page of this tree
	var/datum/codex_tree/other = new /datum/codex_tree(book, /datum/lore/codex/category/main_borealis_lore)
	var/datum/lore/codex/foreign = other.home
	var/datum/lore/codex/before = tree.current_page_of(reader)
	inbox_topic(reader, tree, list("target" = "[REF(foreign)]"))
	TEST_ASSERT_EQUAL(tree.current_page_of(reader), before, "a page that belongs to another codex is refused")
	qdel(other)

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
