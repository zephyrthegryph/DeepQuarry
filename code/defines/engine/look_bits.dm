// What a look applied to an atom (rx_state.look_set_bits): apply_to() takes back, on the next apply, only what an earlier one set
// (code/engine/present/appearance_builder.dm), and the appearance cache keys on the base vars no look has set (code/engine/present/look_cache.dm).
#define LOOK_SET_ICON (1<<0)
#define LOOK_SET_ICON_STATE (1<<1)
#define LOOK_SET_COLOR (1<<2)
#define LOOK_SET_ALPHA (1<<3)
#define LOOK_SET_TRANSFORM (1<<4)
#define LOOK_SET_DIR (1<<5)
#define LOOK_SET_PLANE (1<<6)
#define LOOK_SET_LAYER (1<<7)
#define LOOK_SET_LIGHT (1<<8)
#define LOOK_SET_OFFSET (1<<9)
#define LOOK_SET_INVISIBILITY (1<<10)
