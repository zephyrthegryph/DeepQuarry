var/const/unix_value = UNIX
var/const/windows_value = MS_WINDOWS
var/const/north_value = NORTH
var/const/south_value = SOUTH
var/const/east_value = EAST
var/const/west_value = WEST
var/const/up_value = UP
var/const/down_value = DOWN
/atom/proc/probe()
    return list(plane, pixel_x, pixel_y, pixel_z, pixel_w, appearance_flags, blend_mode, maptext, maptext_x, maptext_y, maptext_width, maptext_height, transform, filters, color, alpha, gender)
/atom/movable/proc/moving()
    return list(bound_x, bound_y, bound_width, bound_height, glide_size, step_size, screen_loc, animate_movement)
/mob/verb/messages(message as message)
    set src = usr.contents
    return message
