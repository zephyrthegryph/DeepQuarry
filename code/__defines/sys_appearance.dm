// Appearance keyed on declared state (doc/rewrite/systems.md section 1).
//
// One line next to a type says how its state is drawn; the runtime (code/datums/sys/appearance.dm)
// builds the combination once per (type, key) in the `decl_appearance` shared cache and re-applies it
// by itself when a declared field it reads changes. Together with DECLARE_APPEARANCE
// (code/__defines/lifecycle_decl.dm: layers keyed on one var) these are the one way to draw state:
//
//   APPEARANCE_TEMPLATE(/obj/machinery/recharger, "recharger{on}{operable}")
//   APPEARANCE_LEVEL(/obj/item/cell, "percent", 4, "{initial(icon_state)}_%p")
//   APPEARANCE_EMISSIVE(/obj/machinery/recharger, "on", list("1" = "recharger-glow"))
//   APPEARANCE_WATCH(/obj/machinery, list("stat", "on"))
//
// Names. A name in a template token, a level, an emissive or a DECLARE_APPEARANCE layer is a var of
// the type or a proc taking no arguments (a derived field such as operable(), or a small reader such
// as percent()). Either way it is read from the instance when the appearance is refreshed.
//
// Template tokens (inside { } in a template or a level format; braces, because DM would read
// [ ] inside a string literal as an embedded expression at the declaration):
//   {name}            the value of name, as text (TRUE is "1", null is "")
//   {name?A:B}        A when name is truthy, else B; A and B are literal text, or @name for the
//                     value of another var ({charging?@icon_state_charging:@icon_state_idle})
//   {initial(name)}   the concrete type's initial value of var name (resolved per subtype)
//
// Refresh is automatic. Every name that is a declared OM field (OM_FIELD, OM_FLAG_FIELD, a
// registered setter, a derived field) adds its channel to the type's appearance watch mask, and APPEARANCE_WATCH adds the channels of fields a procedural update_icon()
// reads. A raise of any of those channels queues the atom once; the presentation lane runs
// update_icon() on it at most once per frame (so a field setter is never followed by a manual
// update_icon()). A name that is not a declared field is read, but its writer still calls
// update_icon() itself.
//
// Order of application: the template's icon_state, then DECLARE_APPEARANCE layers (a layer row with
// an icon_state wins over the template), then level, emissive and slot overlays. The declaration
// owns only the overlays it adds and swaps them on a state change.

/// icon_state from a template over fields (see the { } token syntax above). One per type; a subtype's
/// template replaces its parent's.
#define APPEARANCE_TEMPLATE(PATH, TEMPLATE) _LIFECYCLE_DECL(PATH, set_appearance_template(TEMPLATE))
/// An overlay for a numeric level: VALUE (a var or proc name) is a percentage (0..100), quantized to
/// the nearest of STEPS + 1 levels (0..STEPS). FORMAT is a template where %d is the level and %p the
/// level as a percentage (level * 100 / STEPS). A null VALUE draws nothing.
#define APPEARANCE_LEVEL(PATH, VALUE, STEPS, FORMAT) _LIFECYCLE_DECL(PATH, add_appearance_level(VALUE, STEPS, FORMAT))
/// An emissive overlay keyed on FIELD: ROWS is list("value" = "icon_state", ...) (text keys); a
/// value with no row draws nothing, the "*" row is the fallback.
#define APPEARANCE_EMISSIVE(PATH, FIELD, ROWS) _LIFECYCLE_DECL(PATH, add_appearance_emissive(FIELD, ROWS))
/// The declared fields a procedural update_icon() reads (a list of names): their channels join the
/// watch mask, so a change re-runs update_icon() without a manual call.
#define APPEARANCE_WATCH(PATH, FIELDS) _LIFECYCLE_DECL(PATH, add_appearance_watch(FIELDS))
/// A declared appearance provider: PROC (TYPE_PROC_REF(/atom, appearance_overlays)) computes the overlays from
/// state and returns them (a list of icon_state strings, images or mutable appearances, a single one,
/// or null). It may also set icon_state/color/name, which are presentation. The runtime owns its
/// overlays: it cuts what the provider returned last time and adds the new result, so a provider never
/// calls add_overlay()/cut_overlays(). FIELDS names the declared fields (or raw CHANGE_* channel
/// numbers) the provider reads; a change to any of them re-runs it on the presentation lane. A
/// subtype refines it by overriding the proc (`. = ..()` then add). A provider changes no state.
#define DECLARE_APPEARANCE_PROC(PATH, PROC, FIELDS) _LIFECYCLE_DECL(PATH, set_appearance_proc(PROC, FIELDS))
/// Drops every inherited drawing declaration (template, layers, levels, emissives, slots and the
/// provider): the type keeps whatever icon_state it was mapped or declared with. Watches stay (a
/// machine still refreshes on its core fields). A later line on the same type may declare anew.
#define APPEARANCE_NONE(PATH) _LIFECYCLE_DECL(PATH, clear_appearance())

/// atom.appearance_queued while a latent (unmaterialized) movable has a refresh waiting: it joins the
/// presentation queue when it materializes (appearance_queue(), /atom/proc/materialize()).
#define APPEARANCE_PENDING_LATENT 2

// Template part kinds (code/datums/sys/appearance.dm).
#define APPEARANCE_PART_READ 1
#define APPEARANCE_PART_TERNARY 2
