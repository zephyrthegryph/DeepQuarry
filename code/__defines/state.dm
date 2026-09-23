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
/// Serialize components whose state_mode is STATE_COMPONENT_SAVE.
#define STATE_COMPONENTS (1<<1)
/// Everything: contents and components. What latent entries use.
#define STATE_FULL (STATE_CONTENTS|STATE_COMPONENTS)

/// /datum/component/var/state_mode: what the serializer does with a component.
/// The object is refused while it has this component (relationships, running behaviour).
#define STATE_COMPONENT_REFUSE 0
/// The component is saved as its type plus its saved vars, and re-added on materialize.
#define STATE_COMPONENT_SAVE 1
/// The component is derived state (a cache) and is dropped; it is rebuilt on demand.
#define STATE_COMPONENT_DERIVED 2

/// Default schema version of every type. Bump a type's state_version and add a
/// state_migrate() step when one of its saved vars is renamed, removed or changes meaning.
#define STATE_VERSION_DEFAULT 1
/// The version legacy (pre-L1) flat blobs are read as.
#define STATE_VERSION_LEGACY 0
