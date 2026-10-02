// System accessors (doc/rewrite/final_api.html, section 7 "The graph contract"; section 22). A system's state is private;
// content reads it through the reactive accessor its api.dm declares with SYSTEM_ACCESSOR(system, name, nameof(var)), whose
// declaration sits here so every layer can see it and none names the system. The generator (E5) emits the accessor proc
// into code/engine/_generated/ and teaches generated reads to follow it to the tracked var: a write to the var marks every
// stat that read the accessor for the next drain point (a marked, not an inline, recompute).
//
// Declarations only: a proc never lives in the contracts layer. `analyze gen system_accessors` writes the accessor proc to
// code/engine/_generated/system_accessors.dm (the var must exist on the system: the keys lint checks it).

/// Whether the night-shift system is in night mode (16.11). Read by an APC's wants_night_lights().
SYSTEM_ACCESSOR(nightshift, night_shift_active, nameof(nightshift_active))
