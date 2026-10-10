SYSTEM_DEF(assets)
	name = "Assets"
	needs = list(
		/datum/system/atoms,
		/datum/system/holomaps,
		/datum/system/robot_sprites,
		// pai_icons draws one sprite per chassis the pAI system registers on initialize.
		/datum/system/pai
	)
	var/list/datum/asset_cache_item/cache = list()
	var/list/preload = list()
	var/datum/asset_transport/transport = new()

/datum/system/assets/OnConfigLoad()
	var/newtransporttype = /datum/asset_transport
	switch (CONFIG_GET(string/asset_transport))
		if ("webroot")
			newtransporttype = /datum/asset_transport/webroot

	if (newtransporttype == transport.type)
		return

	var/datum/asset_transport/newtransport = new newtransporttype ()
	if (newtransport.validate_config())
		transport = newtransport
	transport.Load()

/datum/system/assets/initialize()
	#ifdef UNIT_TESTS
	// Focused unit-test runs skip generating every asset and spritesheet at boot
	// (about 2.3 s on the test map). Anything that needs one still gets it:
	// get_asset_datum() builds an asset on first use, which is what the
	// spritesheets and asset tests call. The full suite still loads everything.
	if(unit_test_is_focused_run())
		transport.Initialize(cache)
		return
	#endif
	for(var/type in typesof(/datum/asset))
		var/datum/asset/A = type
		if (type != initial(A._abstract))
			load_asset_datum(type)

	asset_cache_save_hashes()
	transport.Initialize(cache)

