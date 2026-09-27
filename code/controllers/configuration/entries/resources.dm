/datum/config_entry/string/asset_transport

/datum/config_entry/flag/asset_simple_preload

/datum/config_entry/string/asset_cdn_webroot

/datum/config_entry/string/asset_cdn_url

/// Cache generated spritesheets across rounds. The cache is stamped with the
/// build (asset_cache_build_key()) and wiped when the build changes, so it is
/// safe on development servers too.
/datum/config_entry/flag/cache_assets
	default = TRUE

/datum/config_entry/flag/smart_cache_assets

/datum/config_entry/flag/save_spritesheets

/datum/config_entry/string/storage_cdn_iframe
	protection = CONFIG_ENTRY_LOCKED
	default = "https://vorestation.github.io/byond-client-storage/iframe.html"
