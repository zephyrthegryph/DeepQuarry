// tgui-migration (commit 3ec748264e). browse()/datum/browser/admin_log_show panels migrated to TGUI; stale shims (show_browser macro, browse callsites) removed.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/mob/new_player
	var/current_news_page
