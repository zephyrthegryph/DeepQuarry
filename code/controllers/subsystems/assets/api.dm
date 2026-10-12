/// The actual transport selected by the asset system.
/datum/system/assets/proc/current_transport()
	RETURN_TYPE(/datum/asset_transport)
	return transport

/// Accepted/reset CDN configuration enters through the public system boundary.
/datum/system/assets/proc/apply_cdn_url(value)
	if(transport)
		transport.set_url_root(value)

/datum/system/assets/proc/sync_transport_config()
	if(transport && config)
		apply_cdn_url(CONFIG_GET(string/asset_cdn_url))
