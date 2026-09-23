SUBSYSTEM_DEF(assets)
	name = "Assets"
	dependencies = list(
		/datum/controller/subsystem/atoms,
		/datum/controller/subsystem/holomaps,
		/datum/controller/subsystem/robot_sprites
	)
	flags = SS_NO_FIRE
	var/list/datum/asset_cache_item/cache = list()
	var/list/preload = list()
	var/datum/asset_transport/transport = new()

/datum/controller/subsystem/assets/OnConfigLoad()
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

/datum/controller/subsystem/assets/Initialize()
	#ifdef UNIT_TESTS
	// Focused unit-test runs skip generating every asset and spritesheet at boot
	// (about 2.3 s on the test map). Anything that needs one still gets it:
	// get_asset_datum() builds an asset on first use, which is what the
	// spritesheets and asset tests call. The full suite still loads everything.
	if(unit_test_is_focused_run())
		transport.Initialize(cache)
		return SS_INIT_SUCCESS
	#endif
	for(var/type in typesof(/datum/asset))
		var/datum/asset/A = type
		if (type != initial(A._abstract))
			load_asset_datum(type)

	transport.Initialize(cache)

	return SS_INIT_SUCCESS

/datum/controller/subsystem/assets/Recover()
	cache = SSassets.cache
	preload = SSassets.preload
