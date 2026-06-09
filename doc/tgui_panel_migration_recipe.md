# Structured TGUI panel migration recipe

A playbook for converting an `admin_log_show(...)` HTML+href panel into
a properly structured TGUI panel. Each conversion is independent of the
others; pick one panel, follow the recipe, ship.

## When to convert

Convert a panel when:

- It has interactive controls (buttons, inputs, edits) — not pure
  read-only log dumps. Read-only logs are fine staying on the
  `AdminLogViewer` HTML path.
- The HTML body is more than ~50 lines or contains complex logic
  (loops, conditionals beyond simple `if` branches).
- The Topic handler has more than ~3 distinct actions you'd want to
  call out in the UI.

Skip the conversion (use the existing `AdminLogViewer` path) when:

- The panel is a one-shot log dump (e.g. SDQL result, bombers list).
- The panel renders content that lives elsewhere as HTML (e.g. paper
  pencode, antag dossier output).
- The data shape doesn't naturally serialize (raw HTML icons, base64
  blobs embedded mid-string).

## The architectural exemplar

`modular_dq/code/modules/admin/round_status_panel.dm` +
`tgui/packages/tgui/interfaces/RoundStatusPanel.tsx` is the reference.
The player panel rewrite
(`modular_dq/code/modules/admin/player_panel_tgui.dm` +
`tgui/packages/tgui/interfaces/PlayerPanel.tsx`) is the second
example, showing list-with-filter style.

## The recipe

### 1. Locate the legacy HTML builder

Find the proc that builds the HTML body and calls `admin_log_show(...)`.
Note:

- Every `href='byond://?src=\ref[X];key=value'` link
- Every `tgui_input_text/number/list` prompt the Topic handler invokes
- Every "fall-through" pattern (`href_list["xxx"] = 1` re-display)

### 2. Write a panel datum in `modular_dq/code/modules/admin/`

```dm
/datum/MY_PANEL
    var/datum/admins/owner_admin  // or /mob/owner if player-facing

/datum/MY_PANEL/New(owner)
    src.owner_admin = owner

/datum/MY_PANEL/Destroy()
    if(owner_admin?.tgui_MY_PANEL == src)
        owner_admin.tgui_MY_PANEL = null
    owner_admin = null
    return ..()

/datum/MY_PANEL/tgui_state(mob/user)
    return ADMIN_STATE(R_ADMIN)  // or appropriate perm

/datum/MY_PANEL/tgui_interact(mob/user, datum/tgui/ui)
    ui = SStgui.try_update_ui(user, src, ui)
    if(!ui)
        ui = new(user, src, "MyPanel", "Window Title")
        ui.open()

/datum/MY_PANEL/tgui_close(mob/user)
    SStgui.close_uis(src)
    qdel(src)

/datum/MY_PANEL/tgui_data(mob/user)
    return list(
        // STRUCTURED fields. Each Topic href becomes a typed field.
        // List rows become lists of associative lists.
    )

/datum/MY_PANEL/tgui_act(action, list/params, datum/tgui/ui)
    . = ..()
    if(.)
        return
    switch(action)
        if("some_action")
            // Call the same admin proc the legacy Topic handler did.
            SStgui.update_uis(src)  // refresh after state-changing action
            return TRUE
```

Add a `tgui_MY_PANEL` var on the host (usually `/datum/admins`) and a
proc `open_MY_PANEL(client/user)` that lazily creates and opens the
panel. Stash the datum on the host so multiple opens reuse one
instance.

Wire the file into `vorestation.dme` near the other modular_dq admin
files (around line 5732+).

### 3. Write the React component in `tgui/packages/tgui/interfaces/`

```tsx
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  // Match the DM tgui_data shape exactly.
};

export const MyPanel = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Window width={520} height={620} title="…">
      <Window.Content scrollable>
        <Section title="…">
          {/* Components instead of HTML strings */}
          <Button onClick={() => act('some_action')}>Do thing</Button>
        </Section>
      </Window.Content>
    </Window>
  );
};
```

Component file name **must match** the second argument to the
`new /datum/tgui(...)` constructor (e.g. `"MyPanel"` →
`MyPanel.tsx`).

### 4. Replace the legacy proc's body with a one-line call

```dm
/datum/admins/proc/legacy_proc_name(client/user)
    open_MY_PANEL(user)
```

Delete the dead HTML-builder code that's now unreachable. (Leaving it
as a `_legacy_dead` proc creates noise; just remove it.)

### 5. Verify

```
tools\build\build.bat
```

Must show 0 errors, 0 warnings. TGUI rspack must compile cleanly.
`npx biome check tgui/packages/tgui/interfaces/MyPanel.tsx` must
report no issues.

## Common patterns

### Per-row admin actions (PP / PM / VV-style buttons)

DM ships a typed row including `"ref"` (`"\ref[obj]"` string). React
sends `act("action_name", {ref: row.ref})`. The DM `tgui_act` does
`var/atom/target = locate(params["ref"])` then dispatches.

### Re-running BYOND admin verbs

When the legacy Topic handler used `SSadmin_verbs.dynamic_invoke_verb(...)`,
keep that call shape inside the new `tgui_act`. Verbs are still the
canonical way to do admin actions because they handle permissions
logging.

### "Fall-through to re-display" patterns

The legacy `href_list["xxx"] = 1` fall-through that re-opens the same
panel becomes a single `SStgui.update_uis(src)` call after the
state-changing action. The React side automatically gets the fresh
`tgui_data` and re-renders.

### Antag-block / per-type structured data

Some panels embed HTML produced by *other* types' procs (e.g.
`/datum/antagonist/get_check_antag_output`). Those producers also need
a per-type refactor before the consumer can be fully structured.
Pragmatic interim: keep that one HTML blob inside the otherwise
structured data, and render it via `HtmlRenderer` + `forwardTopic`.
RoundStatusPanel does this for the antag block.

### tgui_input_* for one-shot prompts

`tgui_input_text/number/list` already exist and are the right tool
for "ask for a value" inside `tgui_act`. They handle the BYOND
fallback themselves; don't try to roll your own.

## What NOT to do

- **Don't ship raw HTML through `tgui_data`** unless it's a third-party
  output you can't refactor (e.g. antag dossier). The whole point is
  structured state.
- **Don't keep DQEdit markers around dead legacy code.** Delete it —
  the marker is for *changes* to upstream files, not for preserving
  the history of HTML builders we no longer use.
- **Don't reuse the `AdminLogViewer` host-forwarding pattern in new
  panels.** That's the *transitional* shape. Fresh panels should be
  fully structured.
- **Don't create per-window TGUI for every Topic action.** A panel
  with a dozen actions all dispatched via `tgui_act` is fine; one
  panel per action would be wasteful.

## Remaining backlog

As of this commit the following panels are still rendering HTML
through `admin_log_show(...)` and would benefit from a structured
rewrite (in rough priority order):

1. `permissionedit.dm` — rights editor (high admin use)
2. `topic.dm` jobban panel — ban grid
3. `admin.dm` Edit Player / Admin Newscaster / Game Panel
4. `mind.dm` Memory / Edit Memory
5. `event_manager.dm` Event Manager
6. `cataloguer.dm` Catalog display (player UI, ~30s task)
7. `arcade.dm` Orion Trail — full game state machine
8. `talisman.dm`, `scrolls.dm`, `money_bag.dm` — player UI shortlist
9. ~25 more smaller panels

Each follows the recipe above. Estimated 1–3 hours each.
