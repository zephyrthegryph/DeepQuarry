# Window system: docking, tabs and layout for every tgui window

Status: APPROVED by the user's request (2026-11-07); slices (a)-(d) below land in order.

## 1. What exists today (survey)

| Piece | Where | How it is hosted |
|---|---|---|
| Machine, APC, console windows | `interface("Name")` in `CAPABILITIES` -> `ui_window()` -> `/datum/tgui` (`code/library/ui/tgui/tgui.dm`) | One **pooled BYOND window** per open UI (`tgui-window-N`, cloned from the skin's hidden `tgui_window_template`, `tgui_window.dm`). Each window has its own page, its own React store and its own `/datum/tgui`; `ui_data`/`ui_act` route by window id (`session.tgui_windows[id].locked_by`). The page applies its geometry and reveals itself (`tgui/layouts/Window.tsx`, `tgui/reveal.ts`). |
| Pushes | `code/library/ui/tgui/ui_push.dm` | Tracked writes queue a window; phase R delivers at most one `send_update()` per window per tick. |
| Chat | `outputwindow` pane in `rpane.rpanewindow`, or reparented into `chat_float_host` | `code/content/client/floating_chat.dm` (skin params), `tgui-panel/layout/` (drag, snap, dock target, live splitters, all pure maths in `model.ts`). |
| Stat panel tabs (Status, Inspect, Abilities, verb tabs) | `statwindow.statbrowser`, a `/datum/tgui_window` with its own page (`tgui-panel/statpanel/`) | Not tgui UIs: the server pushes named messages (`update_abilities`, ...) and the page sends `Inspect-Act`/`Abilities-Act` to `/client/proc/on_stat_panel_message`. |
| Modal prompts | `code/library/ui/tgui_input/` (`AlertModal`, `InputModal`, ...), tgui-say, tooltip, interaction menu | Pooled or dedicated windows that must stay separate and on top. |

## 2. Host model: the stat panel hosts the frame, each UI keeps its own window

Two models were weighed.

- **One shared host page rendering many interfaces.** Every docked UI would share one browser and one React tree. It needs a
  multi-store tgui backend (today one store per page, `tgui/backend.ts`), per-interface asset and theme isolation, and re-routing
  every message by a sub-id. A crash in one interface would blank them all. Rejected: too much of the frontend changes, and every
  existing interface would be at risk.
- **Separate BYOND windows, framed by the stat panel (chosen).** Each UI stays exactly what it is: its pooled window, page, store
  and `/datum/tgui`. Routing does not change at all. A *docked* UI's window loses its OS chrome (`titlebar=false;can-resize=false`)
  and is placed by the stat panel page over a placeholder the panel lays out in a **dock area** at the top of the column. The
  panel draws everything around the window bodies: the titlebar, tabs, collapse, float and close buttons, the resize grip, and
  the drop targets while dragging. This is the chat float's technique (a frameless window the page positions, `geometry.ts`)
  turned around: the frame is drawn in the panel instead of in the window.

So "dock" is a placement mode of an ordinary window, not a different kind of window, and every `interface()` window docks with no
per-window edit: the shared `Window` layout reads `config.window.docked` and, while docked, drops its own titlebar and never reveals
itself (the panel shows it).

## 3. Routing

Unchanged: `ui_data`/`ui_act`, status and assets go to the window's own page as today. The dock adds three message paths, all keyed
by the pooled window id:

| From | Message | Server | Effect |
|---|---|---|---|
| a UI page | `wm/dock` | `/datum/tgui/on_message` -> `window_dock_of(C).dock(ui)` | the UI becomes docked; full update (config `docked`) |
| a docked UI page | `wm/ready` | `dock.window_ready(ui)` | the panel is told `wm/open {id, interface, title}` |
| stat panel | `WM-View {hidden}` | `dock.set_hidden(ids)` | those UIs stop getting data (section 6) |
| stat panel | `WM-Float {id}`, `WM-Close {id}` | `dock.float(ui)`, `ui.close()` | chrome restored, full update (config `docked = FALSE`) |
| stat panel | `WM-Save {layout}`, `WM-Ready` | the `window_layout` preference; `wm/init` back | persistence (section 5) |
| server | `wm/open`, `wm/close`, `wm/title`, `wm/init` | `stat_panel.send_message()` | the panel reducer |

The panel never trusts its own id list for routing: every `WM-*` message is looked up in the client's session windows and must name a
docked UI the client owns, or it is dropped.

## 4. Layout model (the reducer)

`tgui-panel/statpanel/windowDock.ts` is a pure reducer (tested in `windowDock.test.ts`):

- **State**: `windows` (id -> interface, title), `groups` (ordered; a group is a list of window ids, the active one, `collapsed`,
  `height` in CSS px), `saved` (interface -> placement), a group counter.
- **A group with one window is a list entry; with more it is a tabbed stack.** The dock area is the list of groups.
- **Actions**: `open`, `close`, `title`, `activate`, `collapse`, `resize`, `moveGroup` (reorder), `moveWindow` (into a group as a tab
  at an index, or out into a new group at a list index), `float`, `load` (saved placements).
- **Derived**: `hiddenIds()` (windows in a collapsed group or not the active tab) and `snapshot()` (saved placements). Every action
  re-snapshots, so `saved` always describes what the player last saw.

Drag (slice b) lives in the panel page: a header or tab is dragged with pointer capture; during the drag the panel hides every
docked window so its own drop targets (group headers and the gaps between groups) are visible, then: over a header joins that
group as a tab, over a gap reorders, past the panel's left edge floats (the window keeps its last floating geometry). A floating
window docks with the dock button in its titlebar or by dropping its titlebar drag over the column (`tgui/drag.ts`).

## 5. Persistence

One player preference, `/datum/preference/text/window_layout` (JSON, at most 8 KB): interface name -> `{dock, group, order, tab,
collapsed, height}`. The panel sends it (debounced) as `WM-Save`; the server stores it and reads only `dock` (whether a newly
opened UI of that interface starts docked). On `WM-Ready` the server answers `wm/init {saved, windows}` so a reloaded panel gets
its placements and the windows still docked. A window that is closed and reopened goes back to its group, place and tab.
Floating geometry is the existing per-interface geometry memory (`windowGeometry.ts`), unchanged.

## 6. Performance: hidden windows get no pushes

`/datum/tgui` gains `view_hidden`. While it is set, `send_update()`/`send_full_update()` and the phase R data push only mark
`view_stale` (no `ui_data()` call, no message); status re-checks still run, so a hidden window still closes when its user walks
away. When the panel shows it again, a stale window gets one full update. The panel reports the hidden set only when it changes.
The panel's own placement loop costs one `winset` per window whose rect changed, on resize/scroll and on a 1 s origin check.

## 7. Focus and input

A docked window is still its own OS window: clicking it focuses it and its page's focus handling (`tgui/focus.ts`, return to the
map) is unchanged. The panel's dock chrome returns focus to the map like the rest of the panel (`statpanel/index.tsx`).

## 8. Windows that stay separate

Never docked (no dock button, `dockable = FALSE` in the config, a `wm/dock` from them is refused): non-pooled windows (lobby, media,
tooltip, interaction menu, the stat panel itself), the modal prompts (`GLOB.window_dock_modal_interfaces`: the `tgui_input` and modal
interfaces), and child UIs (`parent_ui`), which follow their parent.

## 9. Slices

- (a) the host: `view_hidden`, `docked`/`dockable` config, the dock area in the stat panel with titlebar, collapse, float and close,
  the dock button on floating windows.
- (b) drag: reorder groups, drag out to float, drag a floating window in to dock.
- (c) groups: tabs, drag a window onto another's header to stack, drag a tab out to its own entry, resize grip.
- (d) persistence: the preference, `WM-Save`/`WM-Ready`/`wm/init`, restore on open.
