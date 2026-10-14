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
 *     (legacy blobs may carry "components" = list(blob, ...), STATE_KEY_COMPONENTS; with
 *      STATE_COMPONENTS they are read back through GLOB.state_legacy_component_vars)
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
 *   state_is_saved(datum/D, var_name)               -> TRUE if var_name is part of D's saved state
 *   state_type_list_default(path, var_name)         -> a latent-safe type's default for a list var
 *                                                      (initial() is null for lists), or null
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
 * Hooks on /obj (override per type, call ..()): state that lives in the object's cap_data records
 * rather than in saved vars (a record cannot be a base-type var; base_vars_lint.py), so it is carried
 * beside the delta under STATE_KEY_EXTRA:
 *   state_extra()                  assoc of name = plain value (numbers, text, lists) to save, or null
 *   state_apply_extra(list/extra)  the decoded assoc written by state_extra(), or null when the blob
 *                                  carried none: restore it (and clear what the blob did not carry)
 *
 * Migrations of renamed or removed types go in GLOB.state_type_migrations
 * ("/old/path" = /new/path, or = null to drop the entry).
 */

/datum
	/// Schema version of this type's saved state. See STATE_VERSION_DEFAULT.
	var/tmp/state_version = STATE_VERSION_DEFAULT


/// Renamed or removed types: "/old/path" = /new/path, or "/old/path" = null to drop blobs of it.
GLOBAL_LIST_INIT(state_type_migrations, list())

/// Component blobs written before components went away (STATE_KEY_COMPONENTS):
/// component type -> list(component var name = the atom var it now lives in).
/// A component type not listed is refused.
GLOBAL_LIST_INIT(state_legacy_component_vars, list(
	"/datum/component/forensics_state" = list(
		"was_bloodied" = "forensic_was_bloodied",
		"blood_color" = "forensic_blood_color",
		"fluorescent" = "forensic_fluorescent",
		"forensic_data" = "forensic_data",
	),
))

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

/// List vars whose Initialize() value can vary per instance (a random roll, or
/// generated from per-instance state). They never take a sampled type baseline,
/// so they are saved whenever non-empty.
/datum/proc/state_nondeterministic_list_vars()
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

/// Per-instance state held outside saved vars (cap_data records), as name = plain value. Return ..() + yours.
/obj/proc/state_extra()
	return null

/// Restores what state_extra() wrote. `extra` is null when the blob carried none: reset to the default.
/obj/proc/state_apply_extra(list/extra)
	return

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
	spent(ctx)

/// Creates a new object from `blob` at `loc`. Returns null on failure.
/proc/state_materialize(list/blob, loc, flags = STATE_FULL, list/errors)
	var/datum/state_context/ctx = new(flags)
	. = ctx.materialize_root(blob, loc)
	if(ctx.errors && errors)
		errors += ctx.errors
	spent(ctx)

/// Writes `blob` onto the existing object `D`. The blob's type must be D's type
/// (after migration). Returns TRUE on success.
/proc/state_apply(datum/D, list/blob, flags = STATE_FULL, list/errors)
	var/datum/state_context/ctx = new(flags)
	. = ctx.apply_root(D, blob)
	if(ctx.errors && errors)
		errors += ctx.errors
	spent(ctx)

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

/// TRUE if `var_name` is part of `D`'s saved state (its type's schema).
/proc/state_is_saved(datum/D, var_name)
	var/datum/state_schema/schema = state_schema_for(D)
	return var_name in schema.saved_vars

/// The default value of list var `var_name` on type `path`, which initial()
/// cannot give. Read from a pristine instance, made once per type, so only
/// latent-safe types (whose Initialize() has no side effects) answer; others
/// return null.
/proc/state_type_list_default(path, var_name)
	var/atom/movable/typed = path
	if(!ispath(path, /atom/movable) || !latent_type_safe(typed))
		return null
	var/datum/state_context/ctx = new(NONE)
	var/list/baseline = ctx.list_baseline_of(path)
	. = isnull(baseline[var_name]) ? null : ctx.decode_value(baseline[var_name])
	spent(ctx)

/// Canonical text of a blob: keys sorted, numbers normalized. Equal state gives equal text.
/proc/state_canonical(list/blob)
	return json_encode(state_canonicalize(blob))

/// A hash of the canonical form. The containment ledger merges entries by it.
/proc/state_hash(list/blob)
	return md5(state_canonical(blob))

/// Logs a state-schema event (failed loads, migrations) to the game log.
/proc/log_state(text)
	log_game("STATE: [text]")

/// Immutable subtype policy rows, built once without constructing any content prototype.
/datum/type_metadata_registry
	var/list/rows

GLOBAL_DATUM(type_metadata_registry, /datum/type_metadata_registry)

/proc/type_metadata_registry()
	RETURN_TYPE(/datum/type_metadata_registry)
	if(!GLOB.type_metadata_registry)
		GLOB.type_metadata_registry = new /datum/type_metadata_registry
		GLOB.type_metadata_registry.register_defaults()
		GLOB.type_metadata_registry.register_test_defaults()
	return GLOB.type_metadata_registry

/datum/type_metadata_registry/proc/register_defaults()
	return

/datum/type_metadata_registry/proc/register_test_defaults()
	return

/datum/type_metadata_registry/proc/register(path, key, value)
	if(!ispath(path, /datum))
		CRASH("type metadata requires a datum type path")
	if(!rows)
		rows = list()
	var/list/policy = rows[path]
	if(!policy)
		policy = list()
		rows[path] = policy
	policy[key] = value

/datum/type_metadata_registry/proc/value(path, key, fallback)
	while(ispath(path, /datum))
		var/list/policy = rows?[path]
		if(policy && (key in policy))
			return policy[key] // FALSE is an explicit override, never an absent value.
		var/datum/typed = path
		path = initial(typed.parent_type)
	return fallback

/proc/type_metadata_value(path, key, fallback)
	return type_metadata_registry().value(path, key, fallback)

/proc/latent_type_safe(path)
	return ispath(path, /atom/movable) && type_metadata_value(path, TYPE_META_LATENT_SAFE, FALSE)

/atom/proc/latent_contents_enabled()
	return type_metadata_value(type, TYPE_META_LATENT_CONTENTS, FALSE)

/atom/proc/latent_idle_delay_value()
	return type_metadata_value(type, TYPE_META_LATENT_IDLE_DELAY, 2 MINUTES)

/atom/movable/proc/slot_hooks_enabled()
	return type_metadata_value(type, TYPE_META_SLOT_HOOKS, FALSE)
