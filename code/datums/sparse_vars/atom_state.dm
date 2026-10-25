// Rare per-instance state of atoms: sparse slots (code/engine/declare/sparse_slots.dm), nothing on /atom until one is set.
// The default each slot reads as is the one the var it replaced was declared with; a write of null clears it.
// Read and write them through sparse_get() / sparse_get_or() / sparse_set(), never through a var of the same name.

// /atom
sparse(/atom, examine_icon_snapshot)
sparse(/atom, tf_offset_x, type = num)
sparse(/atom, tf_offset_y, type = num)
sparse(/atom, last_bumped, type = num)
sparse(/atom, tf_rotation, type = num)
sparse(/atom, tf_scale_x, type = num)
sparse(/atom, tf_scale_y, type = num)

// base_vars wave 3
sparse(/atom, map_json_data)
sparse(/atom, last_damage_flag, type = text)
sparse(/atom, damage_band, type = num)
