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

/// Interfaces that open docked in the right-hand column until the player floats them (the saved layout then says).
GLOBAL_LIST_INIT(window_dock_default_docked, list(
	"Chat" = TRUE,
	"StatPanel" = TRUE,
))

/// Interfaces that never float: they stay docked in the right-hand column whatever the saved layout says, and the column offers
/// no float for them (the column is never without the stat panel).
GLOBAL_LIST_INIT(window_dock_always_docked, list(
	"StatPanel" = TRUE,
))

/datum/tgui
	/// In the right-hand column's page (a column part, column_part.dm) rather than its own native window.
	var/docked = FALSE
	/// Docked and off screen (collapsed, or behind another tab in the column): no data goes out.
	var/view_hidden = FALSE
	/// Data was owed while hidden: one full update when shown.
	var/view_stale = FALSE
	/// Floated out of the column: the screen point ("x,y", physical pixels) its native window opens under, for the update that opens it.
	var/float_at
	/// Opened by a float out of the column: its native window is watched until it shows (float_shown_check()).
	var/floated = FALSE

SCHEMA(/datum/tgui, float_at, schema_text())

/// Whether this interface may live in the column at all: not a modal prompt, not a child of another UI.
/datum/tgui/proc/dockable_interface()
	return !GLOB.window_dock_modal_interfaces[interface] && !parent_ui()

/// Whether this docked UI may leave the column (float, or close): never one that is always docked, never the column's last window
/// (the column is never empty). Content answers (window_dock.dm).
/datum/tgui/proc/may_leave_column(closing)
	return TRUE

/// Whether this UI may dock or float: a pooled native window or a column part, of a dockable interface.
/datum/tgui/proc/dockable()
	return (!!window()?.pooled || istype(window(), /datum/tgui_window/column_part)) && dockable_interface()

/// Shows or hides this docked UI's data: hidden, pushes stop; shown again, a stale UI gets one full update.
/datum/tgui/proc/dock_hide(hidden)
	hidden = !!hidden
	if(view_hidden == hidden)
		return
	view_hidden = hidden
	if(!hidden && view_stale)
		view_stale = FALSE
		send_full_update()

/// Hook: the window a newly opening UI renders in when it belongs in the column (a fresh column part), or null for a pooled native one.
/datum/tgui/proc/dock_window()
	return null

/// Hook: the UI is opening (tgui.dm open()), its window chosen.
/datum/tgui/proc/dock_on_open()
	docked = istype(window(), /datum/tgui_window/column_part)

/// Hook: a docked UI is closing (tgui.dm close()).
/datum/tgui/proc/dock_on_close()
	return

/// A screen point from a page payload (`{x, y}`) as "x,y" text, or null.
/proc/dock_point_text(list/point)
	if(!islist(point) || !isnum(point["x"]) || !isnum(point["y"]))
		return null
	return "[round(point["x"])],[round(point["y"])]"

/// Hook: a dock message from this UI's page (`wm/dock`, `wm/float`, `wm/dropped`, `wm/log`).
/datum/tgui/proc/dock_message(type, list/payload)
	return
