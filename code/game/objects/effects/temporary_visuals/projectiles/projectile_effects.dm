/obj/effect/projectile
	name = "pew"
	icon = 'icons/obj/projectiles.dmi'
	icon_state = "nothing"
	layer = ABOVE_MOB_LAYER
	anchored = TRUE
	mouse_opacity = 0
	appearance_flags = 0

/obj/effect/projectile/singularity_pull()
	return

/obj/effect/projectile/singularity_act()
	return

CAPABILITIES(/obj/effect/projectile)
	param(nameof(angle_at_make), pos = 1)
	param(nameof(p_x_at_make), pos = 2)
	param(nameof(p_y_at_make), pos = 3)
	param(nameof(color_at_make), pos = 4)
	param(nameof(scaling_at_make), pos = 5, apply = PROC_REF(orient))

/obj/effect/projectile/proc/scale_to(nx,ny,override=TRUE)
	var/matrix/M
	if(!override)
		M = transform
	else
		M = new
	M.Scale(nx,ny)
	transform = M

/obj/effect/projectile/proc/turn_to(angle,override=TRUE)
	var/matrix/M
	if(!override)
		M = transform
	else
		M = new
	M.Turn(angle)
	transform = M

/// The tracer's angle, offsets, colour and scale (its constructor params).
/obj/effect/projectile/var/angle_at_make
/obj/effect/projectile/var/p_x_at_make
/obj/effect/projectile/var/p_y_at_make
/obj/effect/projectile/var/color_at_make
/obj/effect/projectile/var/scaling_at_make = 1

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/projectile/proc/orient(scaling)
	if(angle_at_make && p_x_at_make && p_y_at_make && color_at_make && scaling)
		apply_vars(angle_at_make, p_x_at_make, p_y_at_make, color_at_make, scaling)

/obj/effect/projectile/proc/apply_vars(angle_override, p_x = 0, p_y = 0, color_override, scaling = 1, new_loc, increment = 0)
	var/mutable_appearance/look = new(src)
	look.pixel_x = p_x
	look.pixel_y = p_y
	if(color_override)
		look.color = color_override
	appearance = look
	scale_to(1,scaling, FALSE)
	turn_to(angle_override, FALSE)
	if(!isnull(new_loc))	//If you want to null it just delete it...
		forceMove(new_loc)
	for(var/i in 1 to increment)
		pixel_x += round((sin(angle_override)+16*sin(angle_override)*2), 1)
		pixel_y += round((cos(angle_override)+16*cos(angle_override)*2), 1)

/obj/effect/projectile_lighting
	var/owner

CAPABILITIES(/obj/effect/projectile_lighting)
	param(nameof(glow_color), pos = 1)
	param(nameof(glow_range), pos = 2)
	param(nameof(glow_intensity), pos = 3, apply = PROC_REF(glow))
	param(nameof(owner), pos = 4)

/// The light a tracer casts (its constructor params).
/obj/effect/projectile_lighting/var/glow_color
/obj/effect/projectile_lighting/var/glow_range
/obj/effect/projectile_lighting/var/glow_intensity

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/projectile_lighting/proc/glow(intensity)
	set_light(glow_range, glow_intensity, glow_color)
