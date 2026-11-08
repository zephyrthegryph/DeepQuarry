// The docked windows as one chain of native splits (doc/rewrite/proposals/window_system.md section 11): every docked tgui window
// is a pane, laid out by BYOND exactly as the chat pane is. The chain hangs in the stat panel's place in the right-hand column
// (rpane.rpanewindow keeps the chat's layout, code/content/client/floating_chat.dm): link pane 1 (a clone of dock_link_template)
// holds the first docked window and, below it, link pane 2, and so on; the last split holds the last docked window and the stat
// panel. Pure: this file only turns an ordered column into winset parameters; window_dock.dm applies them.

/// The least share of the column an entry keeps (a collapsed entry still shows its header).
#define DOCK_SHARE_MIN 3

/// A link pane's id (n >= 1); its child control is "<id>.split".
/proc/dock_link_id(n)
	return "dock_link_[n]"

/// The pane that stands in the stat panel's place in the right-hand column: the first link when anything is docked.
/proc/dock_column_slot(docked_count)
	return docked_count > 0 ? dock_link_id(1) : SKIN_STAT_PANE

/**
 * The winsets that lay out a column of panes, top to bottom, in the link chain. `entries` are pane ids (the stat panel last);
 * `shares` are their weights in the same order (each split gives its first pane its part of what is left). Returns
 * control id -> params list in the order to apply; n entries use n - 1 splits, link 1 first. Fewer than two entries need none.
 */
/proc/dock_column_winsets(list/entries, list/shares)
	. = list()
	var/count = length(entries)
	if(count < 2)
		return
	var/list/weights = list()
	for(var/i in 1 to count)
		var/weight = (i <= length(shares) && isnum(shares[i])) ? shares[i] : 1
		weights += max(DOCK_SHARE_MIN, weight)
	for(var/split in 1 to count - 1)
		var/rest = 0
		for(var/i in split to count)
			rest += weights[i]
		var/right = (split == count - 1) ? entries[count] : dock_link_id(split + 1)
		.["[dock_link_id(split)].split"] = list(
			"left" = entries[split],
			"right" = right,
			"splitter" = clamp(round(100 * weights[split] / rest), 1, 99),
			"is-vert" = "false",
		)

#undef DOCK_SHARE_MIN
