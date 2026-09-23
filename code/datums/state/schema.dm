/*
 * State schema: the public API (roadmap L1, doc/rewrite/state.md sections 2-5).
 *
 * The schema of a type is its saved vars: every var for which issaved() is true
 * (not tmp, static, global or const), plus a fixed list of built-in appearance
 * vars (STATE_BUILTIN_SAVED). Mark caches, references and runtime handles tmp;
 * tools/ci/state_schema_lint.py flags saved reference vars on latent-safe types.
 *
 * A blob is a plain list that json_encode() writes and json_decode() reads back:
 *
 *   list(
 *     "type" = "/obj/item/pill",       // STATE_KEY_TYPE
 *     "version" = 1,                   // STATE_KEY_VERSION, the type's state_version
 *     "vars" = list(name = value),     // STATE_KEY_VARS, the delta, only if not empty
 *     "contents" = list(blob, ...),    // STATE_KEY_CONTENTS, with STATE_CONTENTS
 *     "components" = list(blob, ...),  // STATE_KEY_COMPONENTS, with STATE_COMPONENTS, only if any
 *   )
 *
 * The delta is the saved vars whose values differ from the type's defaults
 * (initial(); for list vars of latent-safe types, a pristine instance), less
 * those equal to the variant's (state_variant_baseline()).
 *
 * Values are encoded by the codecs in codecs.dm:
 *   number, text, null      as they are
 *   path                    list("#path" = "/type/path")
 *   list                    array, assoc object, or list("#pairs" = list(list(k, v), ...))
 *   child in the subtree    list("#child" = "1.2")  (contents index path)
 *   registry singleton      list("#reg" = list(kind, id))  (material, decl, species, reagent)
 *   file resource           list("#rsc" = "icons/obj/x.dmi")
 *   any other reference     refused: serialization fails and the object stays real
 * A var listed in state_codecs() goes through that codec instead.
 *
 * Global procs (all in this file):
 *   state_serialize(datum/D, flags, list/errors)    -> blob, or null if refused
 *   state_materialize(list/blob, loc, flags, list/errors) -> new object, or null
 *   state_apply(datum/D, list/blob, flags, list/errors)   -> TRUE on success
 *   state_delta(datum/D)                            -> encoded delta, or null if refused
 *   state_canonical(list/blob)                      -> canonical text (sorted keys, normalized numbers)
 *   state_hash(list/blob)                           -> md5 of the canonical text
 *   state_saved_vars(datum/D)                       -> the type's schema: list of saved var names
 *   state_can_serialize(datum/D, flags)             -> TRUE if state_serialize() would succeed
 *   D.state_collapse_blockers(held_refs = 1)        -> reasons D cannot collapse into a latent entry
 *                                                      (collapse.dm): refused refs, timers, processing,
 *                                                      signal registrations, extra refcount()
 *
 * Hooks on /datum (override per type, call ..() where noted):
 *   state_version                  the type's schema version (tmp var)
 *   state_codecs()                 list(var name = /datum/state_codec/... path); return ..() + yours
 *   state_exclude()                saved var names to skip for this instance; return ..() + yours
 *   state_migrate(list/vars, from) upgrade a delta written by an older version; call ..() first
 *   state_variant_baseline()       assoc of var -> value the variant sets, excluded from the delta
 *   state_pre_apply(list/vars, flags)   before vars are written (apply the variant here)
 *   state_post_apply(list/blob, flags)  after vars, contents and components are in place
 *   state_refusal()                a reason text to refuse serialization, or null; call ..()
 *
 * Migrations of renamed or removed types go in GLOB.state_type_migrations
 * ("/old/path" = /new/path, or = null to drop the entry).
 */

/datum
	/// Schema version of this type's saved state. See STATE_VERSION_DEFAULT.
	var/tmp/state_version = STATE_VERSION_DEFAULT

/atom/movable
	/// Latent-safe: instances may collapse into latent entries (containment.md section 4.4).
	/// Its Initialize() has no global side effects and its state serializes. Subtypes inherit it.
	/// The state lint checks every saved var of these types, and dq_state_tests round-trips each one.
	var/tmp/latent_safe = FALSE

/datum/component
	/// What the serializer does with this component: STATE_COMPONENT_REFUSE, _SAVE or _DERIVED.
	var/tmp/state_mode = STATE_COMPONENT_REFUSE

/// Renamed or removed types: "/old/path" = /new/path, or "/old/path" = null to drop blobs of it.
GLOBAL_LIST_INIT(state_type_migrations, list())

/// Built-in vars that belong in the saved state. Every other built-in var is skipped.
#define STATE_BUILTIN_SAVED list("name", "desc", "icon", "icon_state", "dir", "color", "alpha", "pixel_x", "pixel_y", "pixel_w", "pixel_z", "density", "opacity", "invisibility", "gender", "maptext")

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------

/// Per-var codecs: list(var name = /datum/state_codec/... path). Return ..() + yours.
/datum/proc/state_codecs()
	return list()

/// Saved var names this instance does not save right now. Return ..() + yours.
/datum/proc/state_exclude()
	return list()

/// Upgrades `vars` (a decoded delta written at schema version `from_version`)
/// to the current state_version, in place. Call ..() first.
/datum/proc/state_migrate(list/vars, from_version)
	return

/// Assoc list of var name -> value that this instance's variant sets. Vars equal
/// to it are left out of the delta, since state_pre_apply() restores them.
/datum/proc/state_variant_baseline()
	return null

/// Called on the target before the delta's vars are written.
/datum/proc/state_pre_apply(list/vars, flags)
	return

/// Called on the target after vars, contents and components are in place.
/datum/proc/state_post_apply(list/blob, flags)
	return

/// A reason this object's state cannot be serialized right now, or null. Call ..().
/// Running behaviour (timers, processing) does not refuse serialization, since
/// persistence saves running objects; it blocks collapse (collapse.dm).
/datum/proc/state_refusal()
	return null

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

/// Serializes `D` (and, with STATE_CONTENTS, its contents) into a blob.
/// Returns null if anything refuses; the reasons are appended to `errors` if given.
/proc/state_serialize(datum/D, flags = NONE, list/errors)
	var/datum/state_context/ctx = new(flags)
	. = ctx.serialize_root(D)
	if(ctx.errors && errors)
		errors += ctx.errors
	qdel(ctx)

/// Creates a new object from `blob` at `loc`. Returns null on failure.
/proc/state_materialize(list/blob, loc, flags = STATE_FULL, list/errors)
	var/datum/state_context/ctx = new(flags)
	. = ctx.materialize_root(blob, loc)
	if(ctx.errors && errors)
		errors += ctx.errors
	qdel(ctx)

/// Writes `blob` onto the existing object `D`. The blob's type must be D's type
/// (after migration). Returns TRUE on success.
/proc/state_apply(datum/D, list/blob, flags = STATE_FULL, list/errors)
	var/datum/state_context/ctx = new(flags)
	. = ctx.apply_root(D, blob)
	if(ctx.errors && errors)
		errors += ctx.errors
	qdel(ctx)

/// The encoded delta of `D` alone (no contents or components), or null if refused.
/proc/state_delta(datum/D, list/errors)
	var/list/blob = state_serialize(D, NONE, errors)
	if(!blob)
		return null
	return blob[STATE_KEY_VARS] || list()

/// TRUE if state_serialize(D, flags) would succeed.
/proc/state_can_serialize(datum/D, flags = STATE_FULL)
	return !!state_serialize(D, flags)

/// The type's schema: the names of its saved vars, in declaration order.
/proc/state_saved_vars(datum/D)
	var/datum/state_schema/schema = state_schema_for(D)
	return schema.saved_vars.Copy()

/// Canonical text of a blob: keys sorted, numbers normalized. Equal state gives equal text.
/proc/state_canonical(list/blob)
	return json_encode(state_canonicalize(blob))

/// A hash of the canonical form. The containment ledger merges entries by it.
/proc/state_hash(list/blob)
	return md5(state_canonical(blob))

/// Logs a state-schema event (failed loads, migrations) to the game log.
/proc/log_state(text)
	log_game("STATE: [text]")
