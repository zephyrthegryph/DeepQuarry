# Preferences (DeepQuarry)

The original TG/Bay-derived prefs system was rewritten end-to-end for this fork. This document describes the new architecture, where to put what, and how to extend it.

If you're looking for the legacy TG document, the relevant bits are mostly still accurate for `/datum/preference` basics (savefile_key, savefile_identifier, scope) and the corresponding sections below mirror them. The big changes are: no Bay `/datum/category_item/player_setup_item` framework, no per-tab `tgui_data`/`tgui_act`, and a single unified `apply()` instead of `apply_to_X`.

---

## Anatomy of a preference

Every pref is a singleton subtype of `/datum/preference`. Each one declares:

- `savefile_key` — the disk key. Once chosen, don't change it.
- `savefile_identifier` — `PREFERENCE_CHARACTER` (per-character) or `PREFERENCE_PLAYER` (per-account).
- `category` — top-level page in the auto-renderer (e.g. `"identity"`, `"appearance"`, `"loadout"`). See `code/modules/client/preferences/_pref_metadata.dm` for the canonical set.
- `group` — fine sub-section within a category (e.g. category `"appearance"` + group `"hair"`).
- `widget` — UI control hint. Defaults to `PREF_WIDGET_AUTO`, which `get_widget()` resolves by subtype (toggle → boolean, numeric → slider, color → color picker, choiced → dropdown, text → text). Set explicitly for composites (`PREF_WIDGET_HIDDEN` when owned by an editor, `PREF_WIDGET_LONGTEXT` for multi-line).
- `apply()` (or per-type `apply_to_human` / `apply_to_client`) — what happens at character spawn / client login.
- `sanitize()` — coerce a possibly-bad value to a valid one. Runs on load + after constraint-driven invalidation.
- `validate()` — strict accept/reject. Runs before stores.

Example:

```dm
/datum/preference/toggle/human/no_jacket
    key = "no_jacket"
    savefile_identifier = PREFERENCE_CHARACTER
    category = "loadout"
    group = "uniform"

/datum/preference/toggle/human/no_jacket/apply_to_human(target, value)
    target.no_jacket = value
```

That's the whole declaration — no Bay handler, no tgui_data, no copy_to_mob.

## Cross-pref rules: `/datum/preference_constraint`

When one pref's value invalidates another's (species change → reset hair, organ swap → flip the synth flag, etc.), declare a constraint:

```dm
/datum/preference_constraint/species_resets_hair
    triggers = list("species")
    affects = list("hair_style_name")

/datum/preference_constraint/species_resets_hair/apply(preferences, changed_key, old_value, new_value)
    var/list/valid = preferences.get_valid_hairstyles()
    if(!(preferences.read_preference(/datum/preference/text/human/h_style) in valid))
        preferences.update_preference_by_type(/datum/preference/text/human/h_style, pick(valid) || "Bald")
```

Constraints auto-fire from `update_preference()` after the triggering key changes. They're guarded against runaway cascades by `PREF_CONSTRAINT_MAX_DEPTH` (currently 8).

Constraints live in `code/modules/client/preferences/constraints/`.

## Composite UI flows: `/datum/preference_editor`

When a single widget isn't enough (trait picker with budget enforcement, marking color/zone matrix, gear loadout slot builder, etc.), define an editor:

```dm
/datum/preference_editor/trait_picker
    key = "trait_picker"
    category = "traits"
    pref_keys = list("pos_traits", "neu_traits", "neg_traits", ...)

/datum/preference_editor/trait_picker/build_ui_data(preferences)
    return list(...)  // serialize state for the React component

/datum/preference_editor/trait_picker/handle_action(preferences, action, params, user)
    switch(action)
        if("add_trait")
            ...
            return PREF_UPDATE_ACCEPTED
```

On the React side, register a component in `tgui/packages/tgui/interfaces/deepquarry/PreferencesMenu/editors/index.ts` keyed by `editor.key`. The auto-renderer dispatches by string lookup.

Editors live in `code/modules/client/preferences/editors/`.

## Cross-pref orchestration at spawn: `/datum/preference_apply_hook`

For mob-side setup that touches multiple prefs and the character mob (species/trait synthesis, organ application, marking overlays on organs, NIF spawn, body backup), use an apply_hook:

```dm
/datum/preference_apply_hook/markings
    priority = APPLY_HOOK_PRIORITY_ACCESSORIES

/datum/preference_apply_hook/markings/apply(target, preferences)
    // ... rebuild marking overlays on target.organs_by_name
```

Hooks fire after every per-pref `apply()` during `copy_to(character)`, in priority order. The `skip_on_preview` flag opts out for mannequin renders.

Hooks live in `code/modules/client/preferences/apply_hooks/`.

## Save / load / sanitize flow

```
copy_to(character):
    for each PREFERENCE_CHARACTER pref:
        pref.apply(character, value, src)
    for each /datum/preference_apply_hook (priority order):
        hook.apply(character, src)

update_preference(pref, value):
    pref.validate(value)?
    pref.write to in-memory cache
    fire all /datum/preference_constraint subtypes triggered by pref.savefile_key
    auto-save (debounced via begin_update_batch / end_update_batch)

sanitize_preferences():
    for each PREFERENCE_CHARACTER pref:
        pref.sanitize(current_value, src) -> maybe new value
```

Atomic multi-pref updates use `PREF_TRANSACTION_BEGIN(prefs)` / `PREF_TRANSACTION_END(prefs)` so the constraint cascade's disk-write flushes coalesce into one save.

## Where things live

| Path | What |
|---|---|
| `code/modules/client/preferences/_preference.dm` | TG base `/datum/preference` |
| `code/modules/client/preferences/types/` | All pref subtype declarations (TG-style) |
| `code/modules/client/preferences/_preference_dq.dm` | DQ extensions: `group`/`widget`/`depends_on`/`validate`/`sanitize`/`apply`/`get_pref_choices`/`get_widget_props` |
| `code/modules/client/preferences/_preference_constraint.dm` | Constraint base |
| `code/modules/client/preferences/_preference_editor.dm` | Editor base |
| `code/modules/client/preferences/_preference_apply_hook.dm` | Apply-hook base |
| `code/modules/client/preferences/_pref_metadata.dm` | Category/group/widget for inherited prefs (NEW prefs set these directly on the subtype) |
| `code/modules/client/preferences/_pref_sanitizers.dm` | `sanitize()` overrides for inherited prefs |
| `code/modules/client/preferences/_vanity_pref_types.dm` | Pref types copied by `vanity_copy_to` (protean/shapeshift path) |
| `code/modules/client/preferences/constraints/` | Constraint subtypes |
| `code/modules/client/preferences/editors/` | Editor subtypes |
| `code/modules/client/preferences/apply_hooks/` | Apply-hook subtypes |
| `code/modules/client/preferences/middleware/character_setup.dm` | Middleware that assembles the auto-renderer payload |
| `tgui/packages/tgui/interfaces/deepquarry/PreferencesMenu/` | TGUI: window, auto-renderer, widget, editor components |

## Tests

`code/modules/unit_tests/dq_preferences_tests.dm` covers the smoke surface: every pref has a savefile_key + identifier, every visible PREFERENCE_CHARACTER pref has a category, the constraint cascade depth guard holds, batch begin/end nests, composite serialize/deserialize round-trips, `get_widget()` always resolves `PREF_WIDGET_AUTO`.

Run with `bin/test.cmd`.

## Wire protocol (TGUI ↔ DM)

Window data shape:

```ts
{
  dq_categories: [
    {
      category: "appearance",
      groups: [
        { group: "body", items: [PrefWidgetItem | EditorRef, ...] },
        { group: "hair", items: [...] },
        ...
      ]
    },
    ...
  ],
  dq_editor_static?: { [editor_key]: { ... } }  // per-editor static catalog data
}
```

Actions from the window:

- `dq_update_preference` `{ key, value }` — single-pref update; the backend routes through `update_preference()` so constraints fire.
- `dq_editor_action` `{ editor, action, params }` — composite editor's `handle_action()`.

## What used to be here (and is gone)

- `/datum/category_collection/player_setup_collection`
- `/datum/category_group/player_setup_category`
- `/datum/category_item/player_setup_item` and every subtype
- `bay_adapter.dm` middleware
- `tgui/packages/tgui/interfaces/PreferencesMenu/bay_prefs/`
- `tgui/packages/tgui/interfaces/CharacterSetup/`
- Per-tab `tgui_data` / `tgui_act` / `copy_to_mob` / `load_character` / `save_character` / `sanitize_character`
- `player_setup` field + `player_setup.X()` calls
