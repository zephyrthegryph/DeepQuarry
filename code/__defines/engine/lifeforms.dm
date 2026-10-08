// The lifecycle forms (doc/rewrite/final_api.html section 6 "Lifecycle forms"; engine in code/engine/lifeforms/).
//
// Ten declaration forms take the work Initialize() overrides, raw qdel(src) and `usr` did: rolls(), param()/make(), registry()/radio_listen(),
// adjacency(), per_type(), variants(), OWNER/initial_contents()/knows(), starts_as()/derives(), declared lifetimes (lives_while(), the caused endings) and input with
// an actor (click_on(), drag_onto(), hover(), tooltip(), with_actor()). What stays a macro is what a declaration names as a constant.

// ---- entry kinds ----
#define ENTRY_ROLLS "rolls"
#define ENTRY_PARAM "param"
#define ENTRY_BUILT_FROM "built_from"
#define ENTRY_REGISTRY "registry"
#define ENTRY_RADIO_LISTEN "radio_listen"
#define ENTRY_ADJACENCY "adjacency"
#define ENTRY_PER_TYPE "per_type"
#define ENTRY_VARIANTS "variants"
#define ENTRY_CONTAINS "contains"
#define ENTRY_KNOWS "knows"
#define ENTRY_STARTS_AS "starts_as"
#define ENTRY_DERIVES "derives"
#define ENTRY_LIVES_WHILE "lives_while"
#define ENTRY_ON_ENDING "on_ending"
#define ENTRY_INPUT "input_action"
#define ENTRY_TOOLTIP "tooltip"

// ---- lifecycle hook bits of a compiled table (beside ENGINE_HOOK_* of declare.dm) ----
/// The type declares a lifecycle form: the engine's lifeform plan runs at preinit, init and destroy (code/engine/lifeforms/forms.dm).
#define ENGINE_HOOK_LIFEFORMS (1<<7)

// ---- rolls() ----
/// rolls(ROLL_PIXEL, PIXEL_JITTER(n)): the target that is both pixel offsets.
#define ROLL_PIXEL "\[pixel]"
/// A generator: each pixel offset rolled in -n..n (the old randpixel_xy()/pixel_x = rand(-n, n) pair).
#define PIXEL_JITTER(n) roll_gen("jitter", list(n))

// ---- make() / starts_args ----
/// A value a make() call did not pass (the generated make()'s defaults).
#define MAKE_UNSET "\[make:unset]"
/// In starts_args, make_args() or a make() argument: the instance that is creating it (the holder of the starts =, the caller's src).
#define OWNER /datum/lifeform_owner

// ---- registry() ----
/// by = REG_GLOBAL (default): one index for the whole world.
#define REG_GLOBAL 0
/// by = REG_Z: the index is per z-level, and the member moves between them when it changes z.
#define REG_Z (1<<0)
/// by = REG_AREA: the index is per area, and the member moves between them when it changes area.
#define REG_AREA (1<<1)

/// What /atom/movable/Moved() owes the lifecycle forms (the movable's lifeform_moves bits, set at its init).
#define LIFEFORM_MOVES_REGISTRY (1<<0)
#define LIFEFORM_MOVES_ADJACENCY (1<<1)

// ---- adjacency() ----
/// dirs = ADJ_CARDINAL (default) | ADJ_DIAGONALS | ADJ_VERTICAL: the faces a neighbour is looked for on.
#define ADJ_CARDINAL (NORTH|SOUTH|EAST|WEST)
/// The four corners as well (the same bit as the Rust index's DIR_DIAGONALS).
#define ADJ_DIAGONALS (1<<6)
#define ADJ_VERTICAL (UP|DOWN)
/// The smoothing kind: walls, low walls, tables, catwalks, windows and the other structures that join their neighbours' look share it, and
/// each decides through its connects proc which neighbours it joins (a join across types is a shared kind, not a second index).
#define ADJ_KIND_SMOOTH "smooth"
/// Conveyor belts: a belt finds the belts before and after it.
#define ADJ_KIND_CONVEYOR "conveyor"
/// Simulated turfs hearing each other's edges (code/game/turfs/turf_edges.dm): a turf whose edge-relevant state changed has its neighbours' masks
/// recomputed, so a turf's draw reads its own tracked mask and never a neighbour.
#define ADJ_KIND_TURF_EDGE "turf_edge"
/// Every direction a smoothing member looks at: the faces and the corners.
#define ADJ_ALL_AROUND (ADJ_CARDINAL | ADJ_DIAGONALS)
/// Junction bits of the corners in an adjacency() mask (the faces use their BYOND direction bits).
#define ADJ_JUNCTION_NE (1<<6)
#define ADJ_JUNCTION_NW (1<<7)
#define ADJ_JUNCTION_SE (1<<8)
#define ADJ_JUNCTION_SW (1<<9)

// ---- endings ----
/// The causes an "ended" notice carries (/datum/notice/ended, code/engine/lifeforms/lifetimes.dm).
#define END_EXPIRED "expired"
#define END_SPENT "spent"
#define END_CONSUMED "consumed"
#define END_DESTROYED "destroyed"
#define END_DISSOLVED "dissolved"
#define END_REPLACED "replaced"
#define END_SCOPE "scope_ended"
#define END_OWNER "owner_ended"
#define END_ENGINE "engine"

// ---- input actions ----
#define INPUT_CLICK_ON "click_on"
#define INPUT_DRAG_ONTO "drag_onto"
#define INPUT_HOVER "hover"
/// drag_over(): the native MouseDrag while the holder is dragged over something (A.over).
#define INPUT_DRAG_OVER "drag_over"
/// What a click_on()/drag_onto() handler returns to let the type's own native Click()/MouseDrop() (its parent's) run after it.
#define INPUT_FALLTHROUGH "\[input:fallthrough]"
