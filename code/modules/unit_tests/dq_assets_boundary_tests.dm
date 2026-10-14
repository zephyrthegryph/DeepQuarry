/datum/asset_transport/assets_boundary_test
	var/sent_calls = 0
	var/slow_calls = 0
	var/list/slow_files

/datum/asset_transport/assets_boundary_test/send_assets(client/client, list/asset_list)
	sent_calls++
	return asset_list

/datum/asset_transport/assets_boundary_test/send_assets_slow(client/client, list/files, filerate, start)
	slow_calls++
	slow_files = files

/datum/unit_test/dq_assets_boundary/Run()
	// Isolate the cache while retaining the same item references and transport semantics.
	set_var(SSassets, "cache", list())
	set_global("asset_known_hashes", GLOB.asset_known_hashes?.Copy())
	set_global("asset_known_hashes_dirty", GLOB.asset_known_hashes_dirty)
	var/datum/asset_transport/assets_boundary_test/backend = allocate(/datum/asset_transport/assets_boundary_test)
	set_var(SSassets, "transport", backend)
	var/datum/asset_cache_item/item = allocate(/datum/asset_cache_item, "boundary-test.html", 'html/typing_indicator.html', "boundary-test-hash")
	TEST_ASSERT_EQUAL(SSassets.register_asset(item.name, item), item, "Registration must return the registered item")
	TEST_ASSERT_EQUAL(SSassets.cached_asset(item.name), item, "Lookup must preserve item identity")
	TEST_ASSERT_EQUAL(SSassets.register_asset(item.name, item), item, "Duplicate registration must reuse the item")
	TEST_ASSERT_EQUAL(SSassets.transport_type(), backend.type, "Mapping cache keys must use the selected backend type")
	TEST_ASSERT_EQUAL(SSassets.get_asset_url(item.name), backend.get_asset_url(item.name), "URL dispatch changed the transport's result")
	var/list/names = SSassets.cached_asset_names()
	TEST_ASSERT(item.name in names, "The name snapshot must contain the registered asset")
	names.Cut()
	TEST_ASSERT_EQUAL(SSassets.cached_asset(item.name), item, "Mutating a name snapshot must not remove private cache entries")
	var/list/to_send = list()
	to_send[item.name] = item
	TEST_ASSERT_EQUAL(SSassets.send_assets(null, to_send), to_send, "Sending must preserve the caller's associative asset list and transport result")
	TEST_ASSERT_EQUAL(backend.sent_calls, 1, "Sending must reach the selected transport exactly once")
	SSassets.unregister_asset(item.name)
	TEST_ASSERT_NULL(SSassets.cached_asset(item.name), "Unregistration must remove the registered item")
	TEST_ASSERT_NULL(SSassets.get_asset_url(item.name), "An unregistered item must no longer resolve to a URL")

/datum/unit_test/dq_assets_preload_capture/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/asset_transport/assets_boundary_test/original = allocate(/datum/asset_transport/assets_boundary_test)
	var/datum/asset_transport/assets_boundary_test/replacement = allocate(/datum/asset_transport/assets_boundary_test)
	var/list/files = list("boundary-preload.html")
	set_var(original, "preload", files)
	set_var(SSassets, "transport", original)
	SSassets.preload_client(null, 1 SECONDS)
	set_var(SSassets, "transport", replacement)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(original.slow_calls, 1, "A queued login preload must stay with the transport captured at login")
	TEST_ASSERT_EQUAL(length(original.slow_files), 1, "A queued login preload must retain its captured list contents")
	TEST_ASSERT_EQUAL(original.slow_files[1], files[1], "A queued login preload must deliver the captured file name")
	TEST_ASSERT_EQUAL(replacement.slow_calls, 0, "Changing transports must not redirect an already queued login preload")
