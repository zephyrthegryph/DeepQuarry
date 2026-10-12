/datum/asset/simple/dq_native_memo
	_abstract = /datum/asset/simple/dq_native_memo

/datum/asset/group/dq_native_memo
	_abstract = /datum/asset/group/dq_native_memo

/datum/unit_test/dq_asset_memo/proc/restore_asset_state(datum/asset_transport/original_transport, datum/asset/original_simple, datum/asset/original_group, old_url, old_transport_setting)
	SSassets.set_transport(QDELETED(original_transport) ? null : original_transport)
	CONFIG_SET(string/asset_transport, old_transport_setting)
	CONFIG_SET(string/asset_cdn_url, old_url)
	if(!QDELETED(original_simple))
		GLOB.asset_datums[/datum/asset/simple/dq_native_memo] = original_simple
	else
		GLOB.asset_datums -= /datum/asset/simple/dq_native_memo
	if(!QDELETED(original_group))
		GLOB.asset_datums[/datum/asset/group/dq_native_memo] = original_group
	else
		GLOB.asset_datums -= /datum/asset/group/dq_native_memo

/datum/unit_test/dq_asset_memo/proc/prepare_fixture()
	defer_cleanup(src, PROC_REF(restore_asset_state), SSassets.current_transport(), GLOB.asset_datums[/datum/asset/simple/dq_native_memo], GLOB.asset_datums[/datum/asset/group/dq_native_memo], CONFIG_GET(string/asset_cdn_url), CONFIG_GET(string/asset_transport))
	var/datum/asset/simple/dq_native_memo/S = allocate(/datum/asset/simple/dq_native_memo)
	return S

/datum/unit_test/dq_asset_memo/item_inputs/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/T = allocate(/datum/asset_transport)
	SSassets.set_transport(T)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-native-memo.css", icon('icons/effects/effects.dmi'), "memo-item-hash")
	// The actual simple asset source maps this exact item, not a revision.
	S.assets = list("dq-native-memo.css" = I)
	var/before = S.get_serialized_url_mappings()
	I.set_keep_local_name(TRUE)
	var/after = S.get_serialized_url_mappings()
	TEST_ASSERT_NOTEQUAL(before, after, "Changing a real item's URL flag invalidates a warm message")
	var/datum/asset_url_entry/entry = S.url_items["dq-native-memo.css"]
	TEST_ASSERT_EQUAL(entry.item, I, "The memo follows the actual item datum through its real mapping entry")
	TEST_ASSERT_EQUAL(after, TGUI_CREATE_MESSAGE("asset/mappings", list("dq-native-memo.css" = url_encode(I.name))), "Refreshed message contains the public URL projection")
	T.set_dont_mutate_filenames(TRUE)
	I.set_keep_local_name(FALSE)
	TEST_ASSERT_EQUAL(memo_value(S, ASSET_URL_MESSAGE), after, "A real transport flag keeps the same local URL")
	S.reconcile_url_items(list())
	TEST_ASSERT_EQUAL(memo_value(S, ASSET_URL_MESSAGE), TGUI_CREATE_MESSAGE("asset/mappings", list()), "Real membership removal invalidates the warmed view")

/datum/unit_test/dq_asset_memo/configuration/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/webroot/T = allocate(/datum/asset_transport/webroot)
	SSassets.set_transport(T)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-native-memo.css", icon('icons/effects/effects.dmi'), "memo-item-hash")
	S.reconcile_url_items(list("dq-native-memo.css" = I))
	rel_set(S, nameof(S.url_transport), T)
	TEST_ASSERT(CONFIG_SET(string/asset_cdn_url, "https://first.invalid/"), "The real config setter accepts the first prefix")
	var/first = memo_value(S, ASSET_URL_MESSAGE)
	TEST_ASSERT(CONFIG_SET(string/asset_cdn_url, "https://second.invalid/"), "The real config setter accepts a same-type change")
	var/second = memo_value(S, ASSET_URL_MESSAGE)
	TEST_ASSERT_NOTEQUAL(first, second, "Same transport type still invalidates for a changed actual CDN URL")
	TEST_ASSERT_EQUAL(T.url_root, "https://second.invalid/", "Actual transport configuration is updated before query")
	var/datum/config_entry/string/asset_cdn_url/E = config.entries_by_type[/datum/config_entry/string/asset_cdn_url]
	E.set_default()
	TEST_ASSERT_EQUAL(T.url_root, E.config_entry_value, "The real reset route updates transport configuration")
	TEST_ASSERT_NOTEQUAL(memo_value(S, ASSET_URL_MESSAGE), second, "Reset invalidates a warm URL message")

/datum/unit_test/dq_asset_memo/children/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset/group/dq_native_memo/G = allocate(/datum/asset/group/dq_native_memo)
	var/datum/asset_transport/T = allocate(/datum/asset_transport)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-native-child.css", icon('icons/effects/effects.dmi'), "memo-child-hash")
	S.reconcile_url_items(list("dq-native-child.css" = I))
	rel_set(S, nameof(S.url_transport), T)
	var/datum/asset_child_entry/child_entry = allocate(/datum/asset_child_entry)
	rel_set(child_entry, nameof(child_entry.child), S)
	rel_add(G, nameof(G.url_children), child_entry)
	var/first = memo_value(G, ASSET_URL_MESSAGE)
	I.set_legacy(TRUE)
	TEST_ASSERT_NOTEQUAL(memo_value(G, ASSET_URL_MESSAGE), first, "A real nested child's item update invalidates the parent memo")
	rel_take(G, nameof(G.url_children), child_entry)
	TEST_ASSERT_EQUAL(memo_value(G, ASSET_URL_MESSAGE), TGUI_CREATE_MESSAGE("asset/mappings", list()), "Removing the real child updates the parent message")
/datum/config_entry/string/asset_cdn_url/dq_memo_rejected/VASProcCallGuard(str_val)
	return FALSE

/datum/unit_test/dq_asset_memo/rejected_validation/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/webroot/T = allocate(/datum/asset_transport/webroot)
	SSassets.set_transport(T)
	defer_cleanup(src, PROC_REF(restore_rejected_config_entry), config.entries_by_type[/datum/config_entry/string/asset_cdn_url/dq_memo_rejected], config.entries["dq_memo_rejected"])
	var/datum/config_entry/string/asset_cdn_url/dq_memo_rejected/E = allocate(/datum/config_entry/string/asset_cdn_url/dq_memo_rejected)
	T.set_url_root("https://unchanged.invalid/")
	var/old_value = E.config_entry_value
	TEST_ASSERT(!E.ValidateAndSet("https://rejected.invalid/"), "The inherited real string validator honors a rejecting guard")
	TEST_ASSERT_EQUAL(E.config_entry_value, old_value, "Rejected input leaves the actual configuration untouched")
	TEST_ASSERT_EQUAL(T.url_root, "https://unchanged.invalid/", "Rejected input does not publish a copied or stale transport prefix")
	TEST_ASSERT_NOTNULL(S, "Fixture cleanup scope exists")

/datum/unit_test/dq_asset_memo/load_replacement/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/webroot/T = allocate(/datum/asset_transport/webroot)
	SSassets.set_transport(T)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-native-memo.css", icon('icons/effects/effects.dmi'), "memo-item-hash")
	S.reconcile_url_items(list("dq-native-memo.css" = I))
	rel_set(S, nameof(S.url_transport), T)
	CONFIG_SET(string/asset_cdn_url, "https://replacement.invalid/")
	var/first = memo_value(S, ASSET_URL_MESSAGE)
	CONFIG_SET(string/asset_transport, "simple")
	SSassets.OnConfigLoad()
	own(SSassets.current_transport())
	TEST_ASSERT_EQUAL(SSassets.current_transport().type, /datum/asset_transport, "The real config load replaces the transport")
	rel_set(S, nameof(S.url_transport), SSassets.current_transport())
	TEST_ASSERT_NOTEQUAL(memo_value(S, ASSET_URL_MESSAGE), first, "Real transport reference replacement invalidates the warmed message")

/datum/unit_test/dq_asset_memo/deleted_item/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/T = allocate(/datum/asset_transport)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-native-memo.css", icon('icons/effects/effects.dmi'), "memo-item-hash")
	S.reconcile_url_items(list("dq-native-memo.css" = I))
	rel_set(S, nameof(S.url_transport), T)
	var/before = memo_value(S, ASSET_URL_MESSAGE)
	TEST_ASSERT_NOTEQUAL(before, TGUI_CREATE_MESSAGE("asset/mappings", list()), "The warmed view actually contains the item")
	qdel(I)
	TEST_ASSERT_EQUAL(memo_value(S, ASSET_URL_MESSAGE), TGUI_CREATE_MESSAGE("asset/mappings", list()), "Real linked item deletion removes its mapping before memo returns")

/datum/unit_test/dq_asset_memo/aliases_and_regeneration/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/original_transport = SSassets.current_transport()
	defer_cleanup(original_transport, TYPE_PROC_REF(/datum/asset_transport, unregister_asset), "dq-memo-alias-a.css")
	defer_cleanup(original_transport, TYPE_PROC_REF(/datum/asset_transport, unregister_asset), "dq-memo-alias-b.css")
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-memo-source.css", icon('icons/effects/effects.dmi'), "memo-alias-hash")
	S.assets = list("dq-memo-alias-a.css" = I, "dq-memo-alias-b.css" = I)
	S.register()
	var/first = S.get_serialized_url_mappings()
	TEST_ASSERT_EQUAL(length(S.url_items), 2, "Distinct real alias names are preserved for the same item")
	var/datum/asset_url_entry/a = S.url_items["dq-memo-alias-a.css"]
	var/datum/asset_url_entry/b = S.url_items["dq-memo-alias-b.css"]
	TEST_ASSERT_NOTEQUAL(a, b, "Aliases have distinct real mapping entries")
	TEST_ASSERT_EQUAL(a.item, I, "First alias references the real cache item")
	TEST_ASSERT_EQUAL(b.item, I, "Second alias references the same real cache item")
	var/datum/asset_cache_item/replacement = allocate(/datum/asset_cache_item, "dq-memo-replacement.css", icon('icons/effects/effects.dmi'), "memo-replacement-hash")
	S.assets = list("dq-memo-alias-a.css" = replacement)
	// Explicitly unregister the removed alias; regenerate replaces the retained
	// alias through the real transport rather than mutating an opaque cache map.
	original_transport.unregister_asset("dq-memo-alias-b.css")
	S.regenerate()
	var/second = S.get_serialized_url_mappings()
	TEST_ASSERT(QDELETED(a) && QDELETED(b), "Regeneration disposes both real old alias entries and their item links")
	TEST_ASSERT_EQUAL(length(S.url_items), 1, "Regeneration removes the old second alias")
	var/datum/asset_url_entry/current = S.url_items["dq-memo-alias-a.css"]
	TEST_ASSERT_EQUAL(current.item, replacement, "Regeneration retargets the actual retained alias")
	TEST_ASSERT_NOTEQUAL(first, second, "Public URL message refreshes after real regeneration")

/datum/asset/spritesheet/dq_native_memo
	_abstract = /datum/asset/spritesheet/dq_native_memo
	name = "dq_native_memo"
	cross_round_cachable = FALSE

/datum/asset/spritesheet/dq_native_memo/create_spritesheets()
	Insert("nothing", 'icons/effects/effects.dmi', "nothing")

/datum/unit_test/dq_asset_memo/spritesheet_readiness/Run()
	var/datum/asset/simple/dq_native_memo/cleanup_scope = prepare_fixture()
	var/datum/asset_transport/original_transport = SSassets.current_transport()
	defer_cleanup(original_transport, TYPE_PROC_REF(/datum/asset_transport, unregister_asset), "spritesheet_dq_native_memo.css")
	defer_cleanup(original_transport, TYPE_PROC_REF(/datum/asset_transport, unregister_asset), "dq_native_memo_32x32.png")
	var/list/hash_values = list()
	var/list/hash_present = list()
	for(var/key in list("spritesheet_dq_native_memo.css", "dq_native_memo_32x32.png"))
		hash_present[key] = (key in GLOB.asset_known_hashes)
		hash_values[key] = GLOB.asset_known_hashes[key]
	defer_cleanup(src, PROC_REF(restore_sheet_registry), GLOB.asset_datums[/datum/asset/spritesheet/dq_native_memo], hash_values, hash_present, GLOB.asset_known_hashes_dirty)
	var/datum/asset/spritesheet/dq_native_memo/S = allocate(/datum/asset/spritesheet/dq_native_memo)
	var/message = S.get_serialized_url_mappings()
	// Adopt the actual newly-generated cache datums before any assertions;
	// deferred key removal alone would leave their native tracked records alive.
	for(var/key in list("spritesheet_dq_native_memo.css", "dq_native_memo_32x32.png"))
		var/datum/asset_cache_item/generated_item = assets_cache()[key]
		if(!QDELETED(generated_item))
			own(generated_item)
	TEST_ASSERT(S.fully_generated, "The public getter realizes the actual queued sheet before pure memo evaluation")
	TEST_ASSERT_NOTNULL(S.url_items["spritesheet_dq_native_memo.css"], "Prepared view contains the actual registered CSS input")
	TEST_ASSERT_NOTNULL(S.url_items["dq_native_memo_32x32.png"], "Prepared view contains the actual registered PNG input")
	TEST_ASSERT_EQUAL(message, S.get_serialized_url_mappings(), "An unchanged ready sheet reuses an equivalent native message")
	TEST_ASSERT_NOTNULL(cleanup_scope, "Restoration scope is active")

/datum/unit_test/dq_asset_memo/proc/restore_sheet_registry(datum/asset/previous, list/hash_values, list/hash_present, hash_dirty)
	if(!QDELETED(previous))
		GLOB.asset_datums[/datum/asset/spritesheet/dq_native_memo] = previous
	else
		GLOB.asset_datums -= /datum/asset/spritesheet/dq_native_memo
	for(var/key in hash_present)
		if(hash_present[key])
			GLOB.asset_known_hashes[key] = hash_values[key]
		else
			GLOB.asset_known_hashes -= key
	GLOB.asset_known_hashes_dirty = hash_dirty

/datum/unit_test/dq_asset_memo/proc/restore_rejected_config_entry(datum/config_entry/previous, datum/config_entry/previous_named)
	if(!QDELETED(previous))
		config.entries_by_type[/datum/config_entry/string/asset_cdn_url/dq_memo_rejected] = previous
	else
		config.entries_by_type -= /datum/config_entry/string/asset_cdn_url/dq_memo_rejected
	if(!QDELETED(previous_named))
		config.entries["dq_memo_rejected"] = previous_named
	else
		config.entries -= "dq_memo_rejected"

/datum/asset/simple/dq_native_memo/other
	_abstract = /datum/asset/simple/dq_native_memo/other

/datum/unit_test/dq_asset_memo/proc/restore_other_asset(datum/asset/previous)
	if(!QDELETED(previous))
		GLOB.asset_datums[/datum/asset/simple/dq_native_memo/other] = previous
	else
		GLOB.asset_datums -= /datum/asset/simple/dq_native_memo/other

/datum/unit_test/dq_asset_memo/order_overlap/Run()
	var/datum/asset/simple/dq_native_memo/first = prepare_fixture()
	defer_cleanup(src, PROC_REF(restore_other_asset), GLOB.asset_datums[/datum/asset/simple/dq_native_memo/other])
	var/datum/asset/simple/dq_native_memo/other/second = allocate(/datum/asset/simple/dq_native_memo/other)
	var/datum/asset/group/dq_native_memo/G = allocate(/datum/asset/group/dq_native_memo)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-overlap-first.css", icon('icons/effects/effects.dmi'), "first-overlap-hash")
	var/datum/asset_cache_item/J = allocate(/datum/asset_cache_item, "dq-overlap-second.css", icon('icons/effects/effects.dmi'), "second-overlap-hash")
	first.assets = list("overlap.css" = I)
	second.assets = list("overlap.css" = J)
	G.children = list(first.type, second.type)
	var/one = G.get_serialized_url_mappings()
	TEST_ASSERT_EQUAL(one, TGUI_CREATE_MESSAGE("asset/mappings", G.get_url_mappings()), "Native merge matches the actual old overlap consumer")
	G.children = list(second.type, first.type)
	var/two = G.get_serialized_url_mappings()
	TEST_ASSERT_EQUAL(two, TGUI_CREATE_MESSAGE("asset/mappings", G.get_url_mappings()), "Reordering preserves the old merge precedence")
	var/datum/asset_child_entry/first_entry = G.url_children[1]
	var/datum/asset_child_entry/second_entry = G.url_children[2]
	TEST_ASSERT_EQUAL(first_entry.child, second, "Actual prepared child ordering changes immediately")
	TEST_ASSERT_EQUAL(second_entry.child, first, "Both child identities survive the reorder")
	G.children = list(first.type, second.type, first.type)
	var/repeated = G.get_serialized_url_mappings()
	TEST_ASSERT_EQUAL(length(G.url_children), 3, "Repeated actual child positions are preserved")
	TEST_ASSERT_EQUAL(repeated, TGUI_CREATE_MESSAGE("asset/mappings", G.get_url_mappings()), "Repeated-child precedence matches the original consumer")
	var/datum/asset/group/dq_native_memo/outer = allocate(/datum/asset/group/dq_native_memo)
	var/datum/asset_child_entry/nested_entry = allocate(/datum/asset_child_entry)
	rel_set(nested_entry, nameof(nested_entry.child), G)
	rel_add(outer, nameof(outer.url_children), nested_entry)
	TEST_ASSERT_EQUAL(memo_value(outer, ASSET_URL_MESSAGE), TGUI_CREATE_MESSAGE("asset/mappings", G.get_url_mappings()), "Nested groups retain repeated key positions instead of decoding them away")

/datum/unit_test/dq_asset_memo/staging_cycle_recovery/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset/group/dq_native_memo/G = allocate(/datum/asset/group/dq_native_memo)
	G.children = list(G.type)
	var/list/visiting = list()
	var/refused = FALSE
	try
		G.prepare_url_inputs(visiting)
	catch(var/exception/fault)
		refused = TRUE
	TEST_ASSERT(refused, "The real group preparation rejects a cycle before unbounded recursion")
	TEST_ASSERT_EQUAL(length(visiting), 0, "Failure unwinds the actual traversal set completely")
	G.children = list(S.type)
	G.prepare_url_inputs(visiting)
	TEST_ASSERT_EQUAL(length(visiting), 0, "Successful retry also leaves no transient traversal state")
	var/datum/asset_child_entry/entry = G.url_children[1]
	TEST_ASSERT_EQUAL(entry.child, S, "An acyclic retry prepares the actual child after the failure")

/datum/unit_test/dq_asset_memo/deleted_transport/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset/group/dq_native_memo/G = allocate(/datum/asset/group/dq_native_memo)
	var/datum/asset_transport/parent_transport = allocate(/datum/asset_transport)
	var/datum/asset_transport/child_transport = allocate(/datum/asset_transport)
	var/datum/asset_cache_item/parent_item = allocate(/datum/asset_cache_item, "dq-memo-parent.css", icon('icons/effects/effects.dmi'), "parent-item-hash")
	var/datum/asset_cache_item/child_item = allocate(/datum/asset_cache_item, "dq-memo-child.css", icon('icons/effects/effects.dmi'), "child-item-hash")
	G.reconcile_url_items(list("parent.css" = parent_item))
	S.reconcile_url_items(list("child.css" = child_item))
	rel_set(G, nameof(G.url_transport), parent_transport)
	rel_set(S, nameof(S.url_transport), child_transport)
	var/datum/asset_child_entry/entry = allocate(/datum/asset_child_entry)
	rel_set(entry, nameof(entry.child), S)
	rel_add(G, nameof(G.url_children), entry)
	var/list/before = json_decode(memo_value(G, ASSET_URL_MAPPING_JSON))
	TEST_ASSERT_EQUAL(length(before), 2, "Warm projection contains both real own and child mappings")
	qdel(parent_transport)
	var/list/after = json_decode(memo_value(G, ASSET_URL_MAPPING_JSON))
	TEST_ASSERT_EQUAL(length(after), 1, "Deleting the weak own transport omits only the own mapping")
	TEST_ASSERT_NULL(after["parent.css"], "No stale own URL is retained after transport deletion")
	TEST_ASSERT_EQUAL(after["child.css"], child_transport.url_for_item("child.css", child_item), "The live child projection survives the unrelated transport deletion")
	qdel(child_transport)
	TEST_ASSERT_EQUAL(memo_value(S, ASSET_URL_MESSAGE), TGUI_CREATE_MESSAGE("asset/mappings", list()), "A warmed direct memo with no live transport projects an empty own mapping")

// Real superuser UPDATE consumer with actual parsed literal AST shapes.
/datum/unit_test/dq_asset_memo/sdql_identity_setters/Run()
	var/datum/asset/simple/dq_native_memo/S = prepare_fixture()
	var/datum/asset_transport/T = allocate(/datum/asset_transport)
	SSassets.set_transport(T)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "old.css", icon('icons/effects/effects.dmi'), "oldhash")
	S.reconcile_url_items(list("alias.css" = I))
	rel_set(S, nameof(S.url_transport), T)
	var/datum/SDQL2_query/query = allocate(/datum/SDQL2_query, list())
	query.superuser = TRUE
	// SDQL_value strips quote-delimited text tokens; the parser turns numeric
	// tokens into actual numbers before SDQL_expression consumes the AST.
	TEST_ASSERT_EQUAL(query.SDQL_expression(I, list("\"newhash\"")), "newhash", "The actual expression consumer interprets the quoted text AST")
	TEST_ASSERT_EQUAL(query.SDQL_expression(I, list(0)), 0, "The actual expression consumer interprets the numeric AST")
	TEST_ASSERT(!I.vv_edit_var("hash", "forbidden"), "ordinary asset VV policy was weakened")
	var/before = memo_value(S, ASSET_URL_MESSAGE)
	var/list/path = list("hash")
	var/list/sets = list()
	sets[path] = list("\"newhash\"")
	query.SDQL_internal_vv(I, sets)
	TEST_ASSERT_EQUAL(I.hash, "newhash", "superuser UPDATE did not retain permission to change identity")
	TEST_ASSERT_NOTEQUAL(memo_value(S, ASSET_URL_MESSAGE), before, "registered UPDATE returned stale warm memo before observers drained")
	path = list("ext")
	sets = list()
	sets[path] = list("\".png\"")
	query.SDQL_internal_vv(I, sets)
	TEST_ASSERT_EQUAL(memo_value(S, ASSET_URL_MESSAGE), TGUI_CREATE_MESSAGE("asset/mappings", list("alias.css" = url_encode("asset.newhash.png"))), "extension UPDATE did not invalidate the real scalar output")
	I.set_keep_local_name(TRUE)
	before = memo_value(S, ASSET_URL_MESSAGE)
	path = list("name")
	sets = list()
	sets[path] = list("\"new.png\"")
	query.SDQL_internal_vv(I, sets)
	TEST_ASSERT_NOTEQUAL(memo_value(S, ASSET_URL_MESSAGE), before, "name UPDATE returned stale local-name output")
	TEST_ASSERT_EQUAL(I.name, "new.png", "registered setter changed the superuser's exact requested value")
	// Unregistered superuser fields retain the existing bypass policy.
	path = list("superuser")
	sets = list()
	sets[path] = list(0)
	query.SDQL_internal_vv(query, sets)
	TEST_ASSERT_EQUAL(query.superuser, FALSE, "unregistered raw superuser UPDATE was removed")
