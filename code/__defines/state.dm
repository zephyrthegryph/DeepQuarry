// State schema (roadmap L1, doc/rewrite/state.md). The API is in code/datums/state/schema.dm.

/// Blob keys. A blob is a plain list that json_encode() can write.
#define STATE_KEY_TYPE "type"
#define STATE_KEY_VERSION "version"
#define STATE_KEY_VARS "vars"
#define STATE_KEY_CONTENTS "contents"
#define STATE_KEY_COMPONENTS "components"
/// On a child blob: the holder slot it is in, when not the holder's default slot (C5).
#define STATE_KEY_SLOT "slot"
/// Latent entries of a holder (C5): list(list("type", "count", "slot", "state"), ...).
#define STATE_KEY_LATENT "latent"
/// An /obj's state that is not a saved var (its cap_data records): name = encoded value, from /obj/state_extra().
#define STATE_KEY_EXTRA "extra"

/// Wrapper keys for encoded values that JSON cannot hold as they are.
/// A single-key list with one of these keys is a wrapped value; keys of
/// ordinary assoc lists that start with STATE_ESCAPE get one more STATE_ESCAPE.
#define STATE_ESCAPE "#"
#define STATE_WRAP_PATH "#path"
#define STATE_WRAP_CHILD "#child"
#define STATE_WRAP_REGISTRY "#reg"
#define STATE_WRAP_RESOURCE "#rsc"
#define STATE_WRAP_PAIRS "#pairs"
#define STATE_WRAP_OWNED "#owned"

/// Registry kinds for STATE_WRAP_REGISTRY. The value is list(kind, id).
#define STATE_REGISTRY_MATERIAL "material"
#define STATE_REGISTRY_DECL "decl"
#define STATE_REGISTRY_SPECIES "species"
#define STATE_REGISTRY_REAGENT "reagent"

/// Flags for state_serialize() / state_materialize() / state_apply().
/// Serialize the object's contents as children (refused for mobs).
#define STATE_CONTENTS (1<<0)
/// Read back legacy component blobs (saves made before the DCS was deleted) into the
/// entity state that replaced those components (GLOB.state_legacy_component_vars).
#define STATE_COMPONENTS (1<<1)
/// Everything: contents and legacy component blobs. What latent entries use.
#define STATE_FULL (STATE_CONTENTS|STATE_COMPONENTS)

/// Default schema version of every type. Bump a type's state_version and add a
/// state_migrate() step when one of its saved vars is renamed, removed or changes meaning.
#define STATE_VERSION_DEFAULT 1
/// The version legacy (pre-L1) flat blobs are read as.
#define STATE_VERSION_LEGACY 0

// Inherited type policy keys: independent of per-instance state and prototype allocation.
#define TYPE_META_LATENT_SAFE "latent_safe"
#define TYPE_META_LATENT_CONTENTS "latent_contents"
#define TYPE_META_LATENT_IDLE_DELAY "latent_idle_delay"
#define TYPE_META_SLOT_HOOKS "has_slot_hooks"
