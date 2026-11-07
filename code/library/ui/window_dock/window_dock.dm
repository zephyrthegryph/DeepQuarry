// The window dock's library half (doc/rewrite/proposals/window_system.md): the per-window state the transport reads (docked,
// hidden from pushes) and the hooks the transport calls. The dock itself, its messages and the saved layout are client content:
// code/content/client/window_dock.dm implements the hooks.

/// Interfaces that stay separate windows: prompts that must sit on top of everything until answered.
GLOBAL_LIST_INIT(window_dock_modal_interfaces, list(
	"AlertModal" = TRUE,
	"BitfieldInput" = TRUE,
	"CheckboxInput" = TRUE,
	"ColorPickerModal" = TRUE,
	"KeyComboModal" = TRUE,
	"ListInputModal" = TRUE,
	"NumberInputModal" = TRUE,
	"TextInputModal" = TRUE,
))

/datum/tgui
	/// Placed in the stat panel's dock rather than floating (doc/rewrite/proposals/window_system.md).
	var/docked = FALSE
	/// Docked and off screen (collapsed, or behind another tab): no data goes out.
	var/view_hidden = FALSE
	/// Data was owed while hidden: one full update when shown.
	var/view_stale = FALSE

/// Whether this UI may dock: a pooled window, not a modal prompt, not a child of another UI.
/datum/tgui/proc/dockable()
	return !!window()?.pooled && !GLOB.window_dock_modal_interfaces[interface] && !parent_ui()

/// What the stat panel needs to frame this docked UI.
/datum/tgui/proc/dock_entry()
	return list("id" = window()?.id, "interface" = interface, "title" = "[title]")

/// Shows or hides this docked UI's data: hidden, pushes stop; shown again, a stale UI gets one full update.
/datum/tgui/proc/dock_hide(hidden)
	hidden = !!hidden
	if(view_hidden == hidden)
		return
	view_hidden = hidden
	if(!hidden && view_stale)
		view_stale = FALSE
		send_full_update()

/// Hook: the UI is opening (tgui.dm open()); the client's dock decides whether it starts docked.
/datum/tgui/proc/dock_on_open()
	return

/// Hook: a docked UI is closing (tgui.dm close()).
/datum/tgui/proc/dock_on_close()
	return

/// Hook: a dock message from this UI's page (`wm/dock`, `wm/ready`).
/datum/tgui/proc/dock_message(type)
	return
