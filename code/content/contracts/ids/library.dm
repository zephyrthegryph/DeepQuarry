// Ids the shared library (code/library/) names that more than one module reads (doc/rewrite/final_api.html, section 11; section 22 "contracts").
// Declarations only: no procs.

#ifndef SLOT_BELLY_INTERIOR
/// The slot an interior() capability declares: what lives inside the holder (a belly's prey).
#define SLOT_BELLY_INTERIOR "belly_interior"
#endif

/// The slot a buckle() capability declares: the mobs buckled to the holder (a bed's patient, a chair's sitter).
#define SLOT_BUCKLE "buckle"

/// Look layers the library draws (look_layer(name, when = ...)): the part name the icon's "<base>-<name>" state resolves.
#define LOOK_LID "lid"
#define LOOK_FILL_PREFIX "fill"
