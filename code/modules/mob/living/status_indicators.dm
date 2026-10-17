#define STATUS_INDICATOR_Y_OFFSET 2 // Offset from the edge of the icon sprite, so 32 pixels plus whatever number is here.
#define STATUS_INDICATOR_ICON_X_SIZE 16 // Don't need to care about the Y size due to the origin being on the bottom side.
#define STATUS_INDICATOR_ICON_MARGIN 2 // The space between two status indicators.

// 'Status indicators' are icons that display over a mob's head, that visually indicate that the mob is suffering
// from some kind of effect, such as being stunned, blinded, confused, asleep, etc.
// The icons are managed automatically by the mob itself, so that their positions will shift if another indicator is added,
// and it will try to always be above the mob sprite, even for larger sprites like xenos.

/mob/living
	/// icon_states of 'icons/mob/status_indicators.dmi'; null until the first one is added.
	var/list/status_indicators = null

// Adds an icon_state to the list of indicators drawn over the head. The look places them.
/mob/living/proc/add_status_indicator(thing)
	if(get_status_indicator(thing)) // No duplicates, please.
		return
	LAZYADD(status_indicators, "[thing]")

// Similar to above but removes it instead, and nulls the list if it becomes empty as a result.
/mob/living/proc/remove_status_indicator(thing)
	LAZYREMOVE(status_indicators, "[thing]")

/mob/living/proc/get_status_indicator(thing)
	return (("[thing]" in status_indicators) ? "[thing]" : null)

/// The glamour shimmer that plays while a beast shift or polymorph is under way.
/mob/living
	var/glamour_shift = FALSE

/// The row of status indicators over the mob's head, centred on its sprite, whatever its scale (called from the living draw).
/mob/living/proc/look_status_indicators(datum/look/look)
	if(!LAZYLEN(status_indicators))
		return

	if(stat == DEAD || (status_flags & FAKEDEATH))
		return

	var/our_sprite_x = icon_expected_width * get_icon_scale_x()
	var/our_sprite_y = icon_expected_height * get_icon_scale_y()

	var/x_offset = our_sprite_x // Add your own offset here later if you want.
	var/y_offset = our_sprite_y + STATUS_INDICATOR_Y_OFFSET

	// Calculates how 'long' the row of indicators and the margin between them should be.
	// The goal is to have the center of that row be horizontally aligned with the sprite's center.
	var/expected_status_indicator_length = (STATUS_INDICATOR_ICON_X_SIZE * status_indicators.len) + (STATUS_INDICATOR_ICON_MARGIN * max(status_indicators.len - 1, 0))
	var/current_x_position = (x_offset / 2) - (expected_status_indicator_length / 2)

	// The sprite is horizontally shifted when scaled up, so that the center of the sprite doesn't move to the right; the row follows it.
	current_x_position -= (icon_expected_width / 2) * (get_icon_scale_x() - 1)

	for(var/indicator_state in status_indicators)
		// A semi-HUD element: above everything else in the world, but it does not pierce obfuscation such as blindness or darkness.
		look.overlay(look_overlay_image('icons/mob/status_indicators.dmi', indicator_state, layer = HUD_LAYER, plane = PLANE_STATUS, pixel_x = current_x_position, pixel_y = y_offset, appearance_flags = PIXEL_SCALE|TILE_BOUND|NO_CLIENT_COLOR|RESET_COLOR|RESET_ALPHA|RESET_TRANSFORM|KEEP_APART))
		current_x_position += STATUS_INDICATOR_ICON_X_SIZE + STATUS_INDICATOR_ICON_MARGIN


#undef STATUS_INDICATOR_Y_OFFSET
#undef STATUS_INDICATOR_ICON_X_SIZE
#undef STATUS_INDICATOR_ICON_MARGIN
