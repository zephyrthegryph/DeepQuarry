/// Browser assets are owned by this system; callers never select or mutate its transport/cache.
/datum/system/assets/proc/register_asset(asset_name, asset, file_hash, dmi_file_path)
	return transport.register_asset(asset_name, asset, file_hash, dmi_file_path)

/datum/system/assets/proc/unregister_asset(asset_name)
	return transport.unregister_asset(asset_name)

/datum/system/assets/proc/get_asset_url(asset_name, datum/asset_cache_item/asset_cache_item)
	return transport.get_asset_url(asset_name, asset_cache_item)

/datum/system/assets/proc/send_assets(client/client, asset_list)
	return transport.send_assets(client, asset_list)

/// Serialized mapping caches partition by the selected backend, not by its mutable instance.
/datum/system/assets/proc/transport_type()
	return transport.type

/// A cache lookup preserves the registered item's identity without exposing the cache list.
/datum/system/assets/proc/cached_asset(asset_name)
	return cache[asset_name]

/// The webroot loader walks a snapshot of names; it must not mutate the owner's cache.
/datum/system/assets/proc/cached_asset_names()
	var/list/names = list()
	for(var/asset_name in cache)
		names += asset_name
	return names

/datum/system/assets/proc/store_asset(asset_name, datum/asset_cache_item/item)
	cache[asset_name] = item
	return item

/datum/system/assets/proc/forget_asset(asset_name)
	cache[asset_name] = null
	cache.Remove(null)

/// Capture the current transport and preload list now, just as the login timer did.
/// Configuration changes before delivery must not redirect an already queued preload.
/datum/system/assets/proc/preload_client(client/client, delay)
	return after(transport, delay, TYPE_PROC_REF(/datum/asset_transport, send_assets_slow), clock = CLOCK_WORLD, with = list(client, transport.preload))
