// Signed links into the admin viewer (tools/admin-viewer). The viewer has no accounts of its own:
// a staff member opens it from the game, and the link carries who they are, their rights and
// an expiry, signed with the secret both sides share (METRICS_VIEWER_SECRET / VIEWER_SECRET).
//
// rust-g has no HMAC, so the signature is the nested form sha256(secret + sha256(secret + payload)):
// the outer keyed hash stops the length extension a plain sha256(secret + payload) would allow.
// tools/admin-viewer/src/auth.ts verifies the same construction.

/// The signed token for `user`, or null when the viewer isn't configured.
/proc/metrics_viewer_token(client/user)
	var/secret = CONFIG_GET(string/metrics_viewer_secret)
	if(!secret || !user?.holder)
		return null
	var/expires = rustg_unix_timestamp() + CONFIG_GET(number/metrics_viewer_link_minutes) * 60
	var/payload = "[user.ckey]|[user.holder.rank_flags()]|[round(expires)]"
	var/inner = rustg_hash_string(RUSTG_HASH_SHA256, "[secret][payload]")
	var/signature = rustg_hash_string(RUSTG_HASH_SHA256, "[secret][inner]")
	return "[payload]|[signature]"

/// The viewer URL with `user`'s token, or null when the viewer isn't configured.
/proc/metrics_viewer_link(client/user, page = "")
	var/base = CONFIG_GET(string/metrics_viewer_url)
	var/token = metrics_viewer_token(user)
	if(!base || !token)
		return null
	if(copytext(base, -1) == "/")
		base = copytext(base, 1, -1)
	return "[base]/auth?token=[url_encode(token)]&next=[url_encode("/[page]")]"

ADMIN_VERB(open_admin_viewer, R_ADMIN|R_DEBUG|R_SERVER, "Admin Viewer", "Open the server metrics and test history viewer in a game window.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/url = metrics_viewer_link(user)
	if(!url)
		to_chat(user, span_warning("The admin viewer is not configured (METRICS_VIEWER_URL and METRICS_VIEWER_SECRET)."))
		return
	log_admin("[key_name(user)] opened the admin viewer.")
	// A plain browser window that navigates straight to the viewer (WebView2 in 516).
	user << browse("<html><head><meta http-equiv='refresh' content='0;url=[url]'></head><body>Opening the admin viewer...</body></html>", "window=admin_viewer;size=1400x900")

ADMIN_VERB(open_admin_viewer_external, R_ADMIN|R_DEBUG|R_SERVER, "Admin Viewer (Browser)", "Open the server metrics and test history viewer in your own browser.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/url = metrics_viewer_link(user)
	if(!url)
		to_chat(user, span_warning("The admin viewer is not configured (METRICS_VIEWER_URL and METRICS_VIEWER_SECRET)."))
		return
	log_admin("[key_name(user)] opened the admin viewer in their browser.")
	user << link(url)
