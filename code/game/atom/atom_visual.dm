// The BYOND visual built-ins of an atom (color, alpha, layer, plane, the pixel offsets, appearance_flags) are tracked vars: a draw that reads
// one (a worn picture made from an item's tint, an overlay that follows the frame's colour, a limb offset) redraws when it changes, so none of
// them is sampled with read_once(). Each is written through its setter below; a raw write is a `tracked` lint finding. A built-in has no
// generated setter (doc/rewrite/read_driven_tracking.md), so these are hand-written and registered with SETTER().

/// Whether anything reads the built-in `V` of this atom: a stat, an on_change() or derived read, a generated reader of the key or a hop.
#define ATOM_VISUAL_HEARD(V) (GLOB.stat_input_keys?[nameof(V)] || GLOB.derived_read_vars?[nameof(V)] || (length(GLOB.generated_reads_table) && READERS(src, nameof(V))) || draw_hop_reads_var(nameof(V)))

/atom/proc/set_color(new_color)
	if(TRACKED_UNCHANGED(color, new_color))
		return
	color = new_color
	if(ATOM_VISUAL_HEARD(color))
		tracked_changed(src, nameof(color))
SETTER(/atom, color)

/atom/proc/set_alpha(new_alpha)
	if(TRACKED_UNCHANGED(alpha, new_alpha))
		return
	alpha = new_alpha
	if(ATOM_VISUAL_HEARD(alpha))
		tracked_changed(src, nameof(alpha))
SETTER(/atom, alpha)

/atom/proc/set_layer(new_layer)
	if(TRACKED_UNCHANGED(layer, new_layer))
		return
	layer = new_layer
	if(ATOM_VISUAL_HEARD(layer))
		tracked_changed(src, nameof(layer))
SETTER(/atom, layer)

/atom/proc/set_plane(new_plane)
	if(TRACKED_UNCHANGED(plane, new_plane))
		return
	plane = new_plane
	if(ATOM_VISUAL_HEARD(plane))
		tracked_changed(src, nameof(plane))
SETTER(/atom, plane)

/atom/proc/set_appearance_flags(new_flags)
	if(TRACKED_UNCHANGED(appearance_flags, new_flags))
		return
	appearance_flags = new_flags
	if(ATOM_VISUAL_HEARD(appearance_flags))
		tracked_changed(src, nameof(appearance_flags))
SETTER(/atom, appearance_flags)

/atom/proc/set_pixel_x(new_offset)
	if(TRACKED_UNCHANGED(pixel_x, new_offset))
		return
	pixel_x = new_offset
	if(ATOM_VISUAL_HEARD(pixel_x))
		tracked_changed(src, nameof(pixel_x))
SETTER(/atom, pixel_x)

/atom/proc/set_pixel_y(new_offset)
	if(TRACKED_UNCHANGED(pixel_y, new_offset))
		return
	pixel_y = new_offset
	if(ATOM_VISUAL_HEARD(pixel_y))
		tracked_changed(src, nameof(pixel_y))
SETTER(/atom, pixel_y)

/atom/proc/set_pixel_w(new_offset)
	if(TRACKED_UNCHANGED(pixel_w, new_offset))
		return
	pixel_w = new_offset
	if(ATOM_VISUAL_HEARD(pixel_w))
		tracked_changed(src, nameof(pixel_w))
SETTER(/atom, pixel_w)

/atom/proc/set_pixel_z(new_offset)
	if(TRACKED_UNCHANGED(pixel_z, new_offset))
		return
	pixel_z = new_offset
	if(ATOM_VISUAL_HEARD(pixel_z))
		tracked_changed(src, nameof(pixel_z))
SETTER(/atom, pixel_z)

/// The gender an atom is (a mob's biological gender: the body's sprite and its pronouns read it).
/atom/proc/set_gender(new_gender)
	if(TRACKED_UNCHANGED(gender, new_gender))
		return
	gender = new_gender
	if(ATOM_VISUAL_HEARD(gender))
		tracked_changed(src, nameof(gender))
SETTER(/atom, gender)

/// Both ground offsets at once (a walk cycle, a stack of sheets).
/atom/proc/set_pixel_offset(new_x, new_y)
	set_pixel_x(new_x)
	set_pixel_y(new_y)

/// The engine's look applies a colour through this: set_color() publishes it.
/atom/look_set_color(new_color)
	set_color(new_color)

/// The engine's look applies an alpha through this: set_alpha() publishes it.
/atom/look_set_alpha(new_alpha)
	set_alpha(new_alpha)

/// The engine's look applies a plane through this: set_plane() publishes it.
/atom/look_set_plane(new_plane)
	set_plane(new_plane)

/// The engine's look applies a layer through this: set_layer() publishes it.
/atom/look_set_layer(new_layer)
	set_layer(new_layer)

/// The engine's look applies a ground offset through this: set_pixel_offset() publishes it.
/atom/look_set_pixel_offset(new_x, new_y)
	set_pixel_offset(new_x, new_y)
