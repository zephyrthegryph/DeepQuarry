// Presentation entry kinds (doc/rewrite/final_api.html, section 13 "Look" and "Examine"; section 11 "Presentation"). The constructors and the
// collectors are code/engine/present/.

/// examine_line(text | PROC_REF, when =): a line the holder adds to its examine text.
#define ENTRY_EXAMINE_LINE "examine_line"
/// look_layer(name, when =): a named layer of the holder's look, drawn while its condition holds.
#define ENTRY_LOOK_LAYER "look_layer"
