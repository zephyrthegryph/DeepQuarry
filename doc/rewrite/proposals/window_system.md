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

Drag lives in the panel page and is the one DQ model the chat's tab strip uses (`tgui/dq/liveOrder.ts`: drop index,
slide-aside and clamp along one axis, shared by `tgui/dq/Tabs.tsx` along x and `DockArea.tsx` along y). There is no other
drag-to-reorder code for windows:

- **A header's free space** (never a tab or button) drags the whole entry along the list, live: the others slide aside and the
  order commits on release. Dropped on another entry's header it stacks there (`joinGroup`); dragged out of the panel by the chat's
  pop-out distance (`POP_OUT_DISTANCE`, any side) it floats, the shown window under the pointer (`WM-Float {id, at}` ->
  `config.window.float_at`, sent once).
- **A stack's tabs** are the DQ tab strip: a click selects, a drag along the strip re-arranges them live (`orderTabs`), and pulling
  one off the strip (`Tabs` `onDragOut`, `DRAG_OUT_DISTANCE`) hands the drag to the dock: dropped in the list it becomes its own
  entry there (`splitWindow`), on a header it joins that stack, out of the panel it floats under the pointer.
- **A floating window** docks with the dock button in its titlebar or by dropping its titlebar drag over the panel
  (`tgui/drag.ts`, `wm/dock {at}`); a drop goes in the list where it was dropped (`wm/open {at}`), the button at the saved place.
- Collapse to the titlebar is the header's chevron or a double-click on its free space.

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

## 10. How it works in BYOND, what flickers, and the design we keep (2026-11-08)

### 10.1 How a tgui window is made

- The skin (`interface/skin.dmf`) has one hidden window, `tgui_window_template`, holding a single browser control. BYOND cannot
  create a window hidden with `browse()`, so the server **clones** the template (`winclone(client, "tgui_window_template",
  "tgui-window-N")`), makes it invisible (`alpha=0`), and only then `browse()`s the tgui page into it (`tgui_window.dm` `initialize`).
- Those windows are **pooled**: a closed UI keeps its window (suspended, hidden) and the next UI takes it with `acquire_lock()`.
  Opening a machine reuses a window whose page is already loaded, so it is a data message, not a new browser.
- The page sizes and places itself: `Window.tsx` recalls the saved geometry for the interface (`drag.ts`), and `reveal.ts` sends
  size, position and `is-visible`/`alpha` together in one `winset`, so the window never paints at a default size first.
- Every move or resize is a `winset(id, "pos=x,y;size=WxH")` from the page. It goes to the BYOND client, not the server, but it is
  still a native round trip per call. `winget` (asking where something is) is a round trip that waits for an answer.

### 10.2 How docking ("flowing into the right panel") works

Docked windows are **not** drawn inside the stat panel. Each one is still its own BYOND window, with its own browser, page and
`/datum/tgui`. The stat panel page (`statwindow.statbrowser`) draws the frame (header, tabs, collapse, float, close, grip) and an
empty placeholder box per entry. `dockHost.ts` measures each box with `getBoundingClientRect()`, adds the panel's screen origin
(`winget statwindow screen-pos`), and `winset`s the docked window's `pos`/`size` to cover the box exactly. The window has no OS
chrome while docked (`titlebar=false;can-resize=false`). Hidden entries (collapsed, a background tab) get `is-visible=false` and no
data pushes.

The chat is different again: its browser is a real pane (`outputwindow` in the `rpanewindow` child), so BYOND lays it out natively;
floating, it is reparented into its own window (`chat_float_host`).

### 10.3 What causes relayout and flicker

1. **Hide and show.** Until 2026-11-08 every header drag hid every docked window (so the page's drop targets showed) and
   showed them again on release: one `is-visible` flip per window at each end, and the panel repainted under them.
2. **One `winset` per window per change.** Each window that moved was its own `winset`, so a scroll or a resize of the panel moved
   the windows one after another (a visible ripple), each a native round trip.
3. **Polling the origin.** The panel asked BYOND where it is once a second (`winget`) while anything was docked, and re-placed on
   every answer.
4. **Geometry recall on dock/undock.** Floating a window re-runs its geometry recall and reveal (another size+pos+visible winset), and
   the full update re-renders its page.
5. **Re-renders.** Every dock action re-rendered the whole dock area, and every drag frame did too.
6. **Window create/destroy** is already avoided by the pool: dock and undock never destroy or re-create the window, and docking
   changes only the chrome.

### 10.4 The options

- **A. Render docked UIs inside the one panel browser.** No positioning at all and no flicker, but every interface would have to
  run in one page: a multi-store tgui backend, one asset and theme scope per interface, every message re-routed by a sub-id, and one
  crash blanks every docked window. That means rewriting the frontend's core and risking every existing interface. Rejected again.
- **B. Native BYOND panes.** Make each docked window a pane of a child control, so BYOND lays them out. A child control holds only two
  panes. A list means nesting a child per entry, created at runtime with `winset(... "type=child;parent=...")`. That list cannot
  scroll, its splitters only apply on release, and our tabs, collapse and drag would all have to be native controls. Rejected.
- **C. Separate pooled windows, placed by the panel, with the costs removed (chosen).** Keep the window model (it isolates every
  interface and reuses pooled windows), and remove each cause above:
  - windows are **never hidden for a drag**: they ride along with their entry. The live drag moves entries with a CSS transform,
    `getBoundingClientRect()` includes it, and the panel re-places every frame. Drop targets are headers, which windows never cover;
  - **one batched `winset` per frame** for all the windows that moved (`Byond.winset(null, {"id.pos": ..., "id.size": ...})`),
    so they all move in the same native call, and only the ones whose rect changed;
  - the origin is measured **on events** (load, resize, dock change, the start of a drag), with only a slow fallback poll. A docked
    window moves only when its box does;
  - dock and undock **keep the window** (pooled, never destroyed), and a float goes straight to the pointer in the same reveal.

Also part of the one system: floating windows (tgui and the chat) may sit on any monitor; only a lost window (Windows'
-32000 park, or no size) is brought back (`lostRect`, `chat_float_lost`). The right column has one 3px gap between pages: the
stat panel leaves out its frame edge on the chat's side (`html[data-chat-side]`).

What stays: one `winset` per frame while something moves, and a docked window's page re-renders only when its own data changes.
