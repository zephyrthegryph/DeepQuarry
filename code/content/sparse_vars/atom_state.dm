// Rare per-instance state of atoms: sparse slots (code/engine/declare/sparse_slots.dm), nothing on /atom until one is set.
// The default each slot reads as is the one the var it replaced was declared with; a write of null clears it.
// Read and write them through sparse_get() / sparse_get_or() / sparse_set(), never through a var of the same name.

// /atom
// Integrity, set only while the atom is below max_integrity (an intact atom holds nothing): get_integrity() / update_integrity() in atom_defense.dm.
sparse(/atom, atom_integrity, type = num)
// Direction of the last step (the old /atom/movable last_move), written by Move()/doMove(); a stopped mover holds nothing.
sparse(/atom/movable, last_move, type = num)
sparse(/atom, examine_icon_snapshot)
sparse(/atom, tf_offset_x, type = num)
sparse(/atom, tf_offset_y, type = num)
sparse(/atom, tf_rotation, type = num)
// Surface germs (the old /atom germ_level): GERM_LEVEL_AMBIENT while unset, read and written through germs() / set_germs() (organs keep a var).
sparse(/atom, surface_germs, type = num)
// The colours stacked on an atom by priority (the old /atom atom_colours): an interned list, read and written by add/remove_atom_colour().
sparse(/atom, atom_colours, type = list)
sparse(/atom, tf_scale_x, type = num)
sparse(/atom, tf_scale_y, type = num)

// base_vars wave 3
sparse(/atom, map_json_data)
