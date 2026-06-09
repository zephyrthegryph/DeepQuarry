// These are objects that destroy themselves and add themselves to the
// decal list of the floor under them. Use them rather than distinct icon_states
// when mapping in interesting floor designs.
GLOBAL_LIST_EMPTY(floor_decals)

/obj/effect/floor_decal
	name = "floor decal"
	icon = 'icons/turf/flooring/decals_vr.dmi'
	plane = DECAL_PLANE
	layer = DECAL_LAYER
	var/supplied_dir

/obj/effect/floor_decal/Initialize(mapload, newdir, newcolour)
	supplied_dir = newdir
	if(newcolour)
		color = newcolour
	add_to_turf_decals()
	..()
	return INITIALIZE_HINT_QDEL

// This is a separate proc from initialize() to facilitiate its caching and other stuff.  Look into it someday.
/obj/effect/floor_decal/proc/add_to_turf_decals()
	if(supplied_dir)
		set_dir(supplied_dir) // TODO - Why can't this line be done in initialize/New()?
	var/turf/T = get_turf(src)
	if(istype(T, /turf/simulated/floor) || istype(T, /turf/unsimulated/floor) || istype(T, /turf/simulated/shuttle/floor))
		var/cache_key = get_cache_key(T)
		var/image/I = GLOB.floor_decals[cache_key]
		if(!I)
			I = make_decal_image()
			GLOB.floor_decals[cache_key] = I
		LAZYADD(T.decals, I) // Add to its decals list (so it remembers to re-apply after it cuts overlays)
		T.add_overlay(I) // Add to its current overlays too.
		return T

/obj/effect/floor_decal/proc/make_decal_image()
	var/image/I = image(icon = icon, icon_state = icon_state, dir = dir)
	I.layer = MAPPER_DECAL_LAYER
	I.color = color
	I.alpha = alpha
	return I

/obj/effect/floor_decal/proc/get_cache_key(turf/T)
	return "[alpha]-[color]-[dir]-[icon_state]-[T.layer]"

/obj/effect/floor_decal/reset
	name = "reset marker"

/obj/effect/floor_decal/reset/Initialize(mapload)
	..()
	var/turf/T = get_turf(src)
	if(T.decals && T.decals.len)
		T.decals.Cut()
		T.update_icon()
	return INITIALIZE_HINT_QDEL

/obj/effect/floor_decal/corner
	icon_state = "corner_white"

/obj/effect/floor_decal/corner/black
	name = "black corner"
	color = "#333333"

/obj/effect/floor_decal/corner/black/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/black/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/black/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/black/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/black/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/black/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/black/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/black/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/blue
	name = "blue corner"
	color = COLOR_BLUE_GRAY

/obj/effect/floor_decal/corner/blue/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/blue/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/blue/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/blue/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/blue/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/blue/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/blue/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/blue/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/paleblue
	name = "pale blue corner"
	color = COLOR_PALE_BLUE_GRAY

/obj/effect/floor_decal/corner/paleblue/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/paleblue/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/paleblue/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/paleblue/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/paleblue/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/paleblue/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/paleblue/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/paleblue/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/green
	name = "green corner"
	color = COLOR_GREEN_GRAY

/obj/effect/floor_decal/corner/green/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/green/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/green/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/green/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/green/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/green/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/green/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/green/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/lime
	name = "lime corner"
	color = COLOR_PALE_GREEN_GRAY

/obj/effect/floor_decal/corner/lime/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/lime/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/lime/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/lime/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/lime/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/lime/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/lime/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/lime/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/yellow
	name = "yellow corner"
	color = COLOR_BROWN

/obj/effect/floor_decal/corner/yellow/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/yellow/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/yellow/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/yellow/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/yellow/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/yellow/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/yellow/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/yellow/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/yellow/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/beige
	name = "beige corner"
	color = COLOR_BEIGE

/obj/effect/floor_decal/corner/beige/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/beige/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/beige/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/beige/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/beige/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/beige/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/beige/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/beige/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/red
	name = "red corner"
	color = COLOR_RED_GRAY

/obj/effect/floor_decal/corner/red/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/red/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/red/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/red/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/red/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/red/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/red/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/red/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/red/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/pink
	name = "pink corner"
	color = COLOR_PALE_RED_GRAY

/obj/effect/floor_decal/corner/pink/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/pink/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/pink/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/pink/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/pink/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/pink/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/pink/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/pink/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/purple
	name = "purple corner"
	color = COLOR_PURPLE_GRAY

/obj/effect/floor_decal/corner/purple/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/purple/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/purple/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/purple/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/purple/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/purple/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/purple/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/purple/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/mauve
	name = "mauve corner"
	color = COLOR_PALE_PURPLE_GRAY

/obj/effect/floor_decal/corner/mauve/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/mauve/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/mauve/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/mauve/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/mauve/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/mauve/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/mauve/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/mauve/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/orange
	name = "orange corner"
	color = COLOR_DARK_ORANGE

/obj/effect/floor_decal/corner/orange/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/orange/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/orange/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/orange/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/orange/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/orange/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/orange/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/orange/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/brown
	name = "brown corner"
	color = COLOR_DARK_BROWN

/obj/effect/floor_decal/corner/brown/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/brown/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/brown/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/brown/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/brown/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/brown/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/brown/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/brown/bordercee
	icon_state = "bordercolorcee"


/obj/effect/floor_decal/corner/white
	name = "white corner"
	icon_state = "corner_white"

/obj/effect/floor_decal/corner/white/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/white/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/white/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/white/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/white/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/white/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/white/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/white/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/grey
	name = "grey corner"
	color = "#8D8C8C"

/obj/effect/floor_decal/corner/grey/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/grey/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/grey/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/grey/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/grey/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/grey/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/grey/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/grey/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/lightgrey
	name = "lightgrey corner"
	color = "#A8B2B6"

/obj/effect/floor_decal/corner/lightgrey/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/lightgrey/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/lightgrey/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/lightgrey/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/lightgrey/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/lightgrey/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/lightgrey/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/spline/plain
	name = "spline - plain"
	icon_state = "spline_plain"
/obj/effect/floor_decal/spline/plain/corner
	icon_state = "spline_plain_corner"
/obj/effect/floor_decal/spline/plain/cee
	icon_state = "spline_plain_cee"
/obj/effect/floor_decal/spline/plain/three_quarters
	icon_state = "spline_plain_full"

/obj/effect/floor_decal/spline/fancy
	name = "spline - fancy"
	icon_state = "spline_fancy"
/obj/effect/floor_decal/spline/fancy/wood
	name = "spline - wood"
	color = "#CB9E04"
/obj/effect/floor_decal/spline/fancy/wood/corner
	icon_state = "spline_fancy_corner"
/obj/effect/floor_decal/spline/fancy/wood/cee
	icon_state = "spline_fancy_cee"
/obj/effect/floor_decal/spline/fancy/wood/three_quarters
	icon_state = "spline_fancy_full"

/obj/effect/floor_decal/spline/asteroid
	icon = 'icons/turf/floors.dmi'
	icon_state = "asteroid_edge_e"
	name = "rocky edge"

/obj/effect/floor_decal/spline/asteroid/west
	icon_state = "asteroid_edge_w"

/obj/effect/floor_decal/spline/asteroid/east
	icon_state = "asteroid_edge_e"

/obj/effect/floor_decal/spline/asteroid/south
	icon_state = "asteroid_edge_s"

/obj/effect/floor_decal/spline/asteroid/north
	icon_state = "asteroid_edge_n"
	name = "rocky edge"

/obj/effect/floor_decal/industrial/warning
	name = "hazard stripes"
	icon_state = "warning"

/obj/effect/floor_decal/industrial/warning/corner
	icon_state = "warningcorner"

/obj/effect/floor_decal/industrial/warning/full
	icon_state = "warningfull"

/obj/effect/floor_decal/industrial/warning/cee
	icon_state = "warningcee"

/obj/effect/floor_decal/industrial/danger
	name = "hazard stripes"
	icon_state = "danger"

/obj/effect/floor_decal/industrial/danger/corner
	icon_state = "dangercorner"

/obj/effect/floor_decal/industrial/danger/full
	icon_state = "dangerfull"

/obj/effect/floor_decal/industrial/danger/cee
	icon_state = "dangercee"

/obj/effect/floor_decal/industrial/warning/dust
	name = "hazard stripes"
	icon_state = "warning_dust"

/obj/effect/floor_decal/industrial/warning/dust/corner
	name = "hazard stripes"
	icon_state = "warningcorner_dust"

/obj/effect/floor_decal/industrial/hatch
	name = "hatched marking"
	icon_state = "delivery"

/obj/effect/floor_decal/industrial/hatch/yellow
	color = "#CFCF55"

/obj/effect/floor_decal/industrial/outline
	name = "white outline"
	icon_state = "outline"

/obj/effect/floor_decal/industrial/outline/blue
	name = "blue outline"
	color = "#00B8B2"

/obj/effect/floor_decal/industrial/outline/yellow
	name = "yellow outline"
	color = "#CFCF55"

/obj/effect/floor_decal/industrial/outline/grey
	name = "grey outline"
	color = "#808080"

/obj/effect/floor_decal/industrial/outline/red
	name = "red outline"
	color = COLOR_RED

/obj/effect/floor_decal/industrial/loading
	name = "loading area"
	icon_state = "loadingarea"

/obj/effect/floor_decal/plaque
	name = "plaque"
	icon_state = "plaque"

/obj/effect/floor_decal/plaque/yw
	name = "Commerative Plaque"
	icon = 'icons/obj/structures_yw32x32.dmi'
	icon_state = "plaque"
	desc = "A plaque commerating the building efforts of the sleepiest outpost in the sector, Yawn Wider."

/obj/effect/floor_decal/carpet
	name = "carpet"
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_state = "carpet_edges"

/obj/effect/floor_decal/carpet/blue
	name = "carpet"
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_state = "bcarpet_edges"

/obj/effect/floor_decal/carpet/corners
	name = "carpet"
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_state = "carpet_corners"

/obj/effect/floor_decal/asteroid
	name = "random asteroid rubble"
	icon_state = "asteroid0"

/obj/effect/floor_decal/asteroid/Initialize(mapload, newdir, newcolour)
	icon_state = "asteroid[rand(0,9)]"
	. = ..()

/obj/effect/floor_decal/chapel
	name = "chapel"
	icon_state = "chapel"

/obj/effect/floor_decal/ss13/l1
	name = "L1"
	icon_state = "L1"

/obj/effect/floor_decal/ss13/l2
	name = "L2"
	icon_state = "L2"

/obj/effect/floor_decal/ss13/l3
	name = "L3"
	icon_state = "L3"

/obj/effect/floor_decal/ss13/l4
	name = "L4"
	icon_state = "L4"

/obj/effect/floor_decal/ss13/l5
	name = "L5"
	icon_state = "L5"

/obj/effect/floor_decal/ss13/l6
	name = "L6"
	icon_state = "L6"

/obj/effect/floor_decal/ss13/l7
	name = "L7"
	icon_state = "L7"

/obj/effect/floor_decal/ss13/l8
	name = "L8"
	icon_state = "L8"

/obj/effect/floor_decal/ss13/l9
	name = "L9"
	icon_state = "L9"

/obj/effect/floor_decal/ss13/l10
	name = "L10"
	icon_state = "L10"

/obj/effect/floor_decal/ss13/l11
	name = "L11"
	icon_state = "L11"

/obj/effect/floor_decal/ss13/l12
	name = "L12"
	icon_state = "L12"

/obj/effect/floor_decal/ss13/l13
	name = "L13"
	icon_state = "L13"

/obj/effect/floor_decal/ss13/l14
	name = "L14"
	icon_state = "L14"

/obj/effect/floor_decal/ss13/l15
	name = "L15"
	icon_state = "L15"

/obj/effect/floor_decal/ss13/l16
	name = "L16"
	icon_state = "L16"

/obj/effect/floor_decal/sign
	name = "floor sign"
	icon_state = "white_1"

/obj/effect/floor_decal/sign/two
	icon_state = "white_2"

/obj/effect/floor_decal/sign/a
	icon_state = "white_a"

/obj/effect/floor_decal/sign/b
	icon_state = "white_b"

/obj/effect/floor_decal/sign/c
	icon_state = "white_c"

/obj/effect/floor_decal/sign/d
	icon_state = "white_d"

/obj/effect/floor_decal/sign/ex
	icon_state = "white_ex"

/obj/effect/floor_decal/sign/m
	icon_state = "white_m"

/obj/effect/floor_decal/sign/cmo
	icon_state = "white_cmo"

/obj/effect/floor_decal/sign/v
	icon_state = "white_v"

/obj/effect/floor_decal/sign/p
	icon_state = "white_p"

/obj/effect/floor_decal/sign/small_a
	icon_state = "small_a"

/obj/effect/floor_decal/sign/small_b
	icon_state = "small_b"

/obj/effect/floor_decal/sign/small_c
	icon_state = "small_c"

/obj/effect/floor_decal/sign/small_d
	icon_state = "small_d"

/obj/effect/floor_decal/sign/small_e
	icon_state = "small_e"

/obj/effect/floor_decal/sign/small_f
	icon_state = "small_f"

/obj/effect/floor_decal/sign/small_g
	icon_state = "small_g"

/obj/effect/floor_decal/sign/small_h
	icon_state = "small_h"

/obj/effect/floor_decal/sign/small_1
	icon_state = "small_1"

/obj/effect/floor_decal/sign/small_2
	icon_state = "small_2"

/obj/effect/floor_decal/sign/small_3
	icon_state = "small_3"

/obj/effect/floor_decal/sign/small_4
	icon_state = "small_4"

/obj/effect/floor_decal/sign/small_5
	icon_state = "small_5"

/obj/effect/floor_decal/sign/small_6
	icon_state = "small_6"

/obj/effect/floor_decal/sign/small_7
	icon_state = "small_7"

/obj/effect/floor_decal/sign/small_8
	icon_state = "small_8"

/obj/effect/floor_decal/sign/dock
	icon_state = "white_d"

/obj/effect/floor_decal/sign/dock/one
	icon_state = "white_d1"

/obj/effect/floor_decal/sign/dock/two
	icon_state = "white_d2"

/obj/effect/floor_decal/sign/dock/three
	icon_state = "white_d3"

/obj/effect/floor_decal/rust
	name = "rust"
	icon_state = "rust"

/obj/effect/floor_decal/rust/mono_rusted1
	icon_state = "mono_rusted1"

/obj/effect/floor_decal/rust/mono_rusted2
	icon_state = "mono_rusted2"

/obj/effect/floor_decal/rust/mono_rusted3
	icon_state = "mono_rusted3"

/obj/effect/floor_decal/rust/part_rusted1
	icon_state = "part_rusted1"

/obj/effect/floor_decal/rust/part_rusted2
	icon_state = "part_rusted2"

/obj/effect/floor_decal/rust/part_rusted3
	icon_state = "part_rusted3"

/obj/effect/floor_decal/rust/color_rusted
	icon_state = "color_rusted"

/obj/effect/floor_decal/rust/color_rustedcorner
	icon_state = "color_rustedcorner"

/obj/effect/floor_decal/rust/color_rustedfull
	icon_state = "color_rustedfull"

/obj/effect/floor_decal/rust/color_rustedcee
	icon_state = "color_rustedcee"

/obj/effect/floor_decal/rust/steel_decals_rusted1
	icon_state = "steel_decals_rusted1"

/obj/effect/floor_decal/rust/steel_decals_rusted2
	icon_state = "steel_decals_rusted2"

//Old tile

/obj/effect/floor_decal/corner_oldtile
	name = "corner oldtile"
	icon_state = "corner_oldtile"

/obj/effect/floor_decal/corner_oldtile/white
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#d9d9d9"

/obj/effect/floor_decal/corner_oldtile/white/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/white/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/blue
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#8ba7ad"

/obj/effect/floor_decal/corner_oldtile/blue/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/blue/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/yellow
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#8c6d46"

/obj/effect/floor_decal/corner_oldtile/yellow/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/yellow/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/gray
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#687172"

/obj/effect/floor_decal/corner_oldtile/gray/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/gray/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/beige
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#385e60"

/obj/effect/floor_decal/corner_oldtile/beige/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/beige/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/red
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#964e51"

/obj/effect/floor_decal/corner_oldtile/red/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/red/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/purple
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#906987"

/obj/effect/floor_decal/corner_oldtile/purple/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/purple/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

/obj/effect/floor_decal/corner_oldtile/green
	name = "corner oldtile"
	icon_state = "corner_oldtile"
	color = "#46725c"

/obj/effect/floor_decal/corner_oldtile/green/diagonal
	name = "corner oldtile diagonal"
	icon_state = "corner_oldtile_diagonal"

/obj/effect/floor_decal/corner_oldtile/green/full
	name = "corner oldtile full"
	icon_state = "corner_oldtile_full"

//Kafel

/obj/effect/floor_decal/corner_kafel
	name = "corner kafel"
	icon_state = "corner_kafel"

/obj/effect/floor_decal/corner_kafel/white
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#d9d9d9"

/obj/effect/floor_decal/corner_kafel/white/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/white/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/blue
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#8ba7ad"

/obj/effect/floor_decal/corner_kafel/blue/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/blue/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/yellow
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#8c6d46"

/obj/effect/floor_decal/corner_kafel/yellow/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/yellow/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/gray
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#687172"

/obj/effect/floor_decal/corner_kafel/gray/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/gray/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/beige
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#385e60"

/obj/effect/floor_decal/corner_kafel/beige/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/beige/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/red
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#964e51"

/obj/effect/floor_decal/corner_kafel/red/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/red/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/purple
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#906987"

/obj/effect/floor_decal/corner_kafel/purple/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/purple/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

/obj/effect/floor_decal/corner_kafel/green
	name = "corner kafel"
	icon_state = "corner_kafel"
	color = "#46725c"

/obj/effect/floor_decal/corner_kafel/green/diagonal
	name = "corner kafel diagonal"
	icon_state = "corner_kafel_diagonal"

/obj/effect/floor_decal/corner_kafel/green/full
	name = "corner kafel full"
	icon_state = "corner_kafel_full"

//Techfloor

/obj/effect/floor_decal/corner_techfloor_gray
	name = "corner techfloorgray"
	icon_state = "corner_techfloor_gray"

/obj/effect/floor_decal/corner_techfloor_gray/diagonal
	name = "corner techfloorgray diagonal"
	icon_state = "corner_techfloor_gray_diagonal"

/obj/effect/floor_decal/corner_techfloor_gray/full
	name = "corner techfloorgray full"
	icon_state = "corner_techfloor_gray_full"

/obj/effect/floor_decal/corner_techfloor_grid
	name = "corner techfloorgrid"
	icon_state = "corner_techfloor_grid"

/obj/effect/floor_decal/corner_techfloor_grid/diagonal
	name = "corner techfloorgrid diagonal"
	icon_state = "corner_techfloor_grid_diagonal"

/obj/effect/floor_decal/corner_techfloor_grid/full
	name = "corner techfloorgrid full"
	icon_state = "corner_techfloor_grid_full"

/obj/effect/floor_decal/corner_steel_grid
	name = "corner steel_grid"
	icon_state = "steel_grid"

/obj/effect/floor_decal/corner_steel_grid/diagonal
	name = "corner tsteel_grid diagonal"
	icon_state = "steel_grid_diagonal"

/obj/effect/floor_decal/corner_steel_grid/full
	name = "corner steel_grid full"
	icon_state = "steel_grid_full"

/obj/effect/floor_decal/borderfloor
	name = "border floor"
	icon_state = "borderfloor"

/obj/effect/floor_decal/borderfloor/corner
	icon_state = "borderfloorcorner"

/obj/effect/floor_decal/borderfloor/corner2
	icon_state = "borderfloorcorner2"

/obj/effect/floor_decal/borderfloor/full
	icon_state = "borderfloorfull"

/obj/effect/floor_decal/borderfloor/cee
	icon_state = "borderfloorcee"

/obj/effect/floor_decal/borderfloorblack
	name = "border floor"
	icon_state = "borderfloor_black"

/obj/effect/floor_decal/borderfloorblack/corner
	icon_state = "borderfloorcorner_black"

/obj/effect/floor_decal/borderfloorblack/corner2
	icon_state = "borderfloorcorner2_black"

/obj/effect/floor_decal/borderfloorblack/full
	icon_state = "borderfloorfull_black"

/obj/effect/floor_decal/borderfloorblack/cee
	icon_state = "borderfloorcee_black"

/obj/effect/floor_decal/borderfloorwhite
	name = "border floor"
	icon_state = "borderfloor_white"

/obj/effect/floor_decal/borderfloorwhite/corner
	icon_state = "borderfloorcorner_white"

/obj/effect/floor_decal/borderfloorwhite/corner2
	icon_state = "borderfloorcorner2_white"

/obj/effect/floor_decal/borderfloorwhite/full
	icon_state = "borderfloorfull_white"

/obj/effect/floor_decal/borderfloorwhite/cee
	icon_state = "borderfloorcee_white"

/obj/effect/floor_decal/steeldecal
	name = "steel decal"
	icon_state = "steel_decals1"

/obj/effect/floor_decal/steeldecal/steel_decals1
	icon_state = "steel_decals1"

/obj/effect/floor_decal/steeldecal/steel_decals2
	icon_state = "steel_decals2"

/obj/effect/floor_decal/steeldecal/steel_decals3
	icon_state = "steel_decals3"

/obj/effect/floor_decal/steeldecal/steel_decals4
	icon_state = "steel_decals4"

/obj/effect/floor_decal/steeldecal/steel_decals5
	icon_state = "steel_decals5"

/obj/effect/floor_decal/steeldecal/steel_decals6
	icon_state = "steel_decals6"

/obj/effect/floor_decal/steeldecal/steel_decals7
	icon_state = "steel_decals7"

/obj/effect/floor_decal/steeldecal/steel_decals8
	icon_state = "steel_decals8"

/obj/effect/floor_decal/steeldecal/steel_decals9
	icon_state = "steel_decals9"

/obj/effect/floor_decal/steeldecal/steel_decals10
	icon_state = "steel_decals10"

/obj/effect/floor_decal/steeldecal/steel_decals_central1
	icon_state = "steel_decals_central1"

/obj/effect/floor_decal/steeldecal/steel_decals_central2
	icon_state = "steel_decals_central2"

/obj/effect/floor_decal/steeldecal/steel_decals_central3
	icon_state = "steel_decals_central3"

/obj/effect/floor_decal/steeldecal/steel_decals_central4
	icon_state = "steel_decals_central4"

/obj/effect/floor_decal/steeldecal/steel_decals_central5
	icon_state = "steel_decals_central5"

/obj/effect/floor_decal/steeldecal/steel_decals_central6
	icon_state = "steel_decals_central6"

/obj/effect/floor_decal/steeldecal/steel_decals_central7
	icon_state = "steel_decals_central7"

/obj/effect/floor_decal/steeldecal/monofloor
	icon_state = "monofloor"

/obj/effect/floor_decal/techfloor
	name = "techfloor edges"
	icon_state = "techfloor_edges"

/obj/effect/floor_decal/techfloor/corner
	name = "techfloor corner"
	icon_state = "techfloor_corners"

/obj/effect/floor_decal/techfloor/orange
	name = "techfloor edges"
	icon_state = "techfloororange_edges"

/obj/effect/floor_decal/techfloor/orange/corner
	name = "techfloor corner"
	icon_state = "techfloororange_corners"

/obj/effect/floor_decal/techfloor/hole
	name = "hole left"
	icon_state = "techfloor_hole_left"

/obj/effect/floor_decal/techfloor/hole/right
	name = "hole right"
	icon_state = "techfloor_hole_right"


//Grass for ship garden

/obj/effect/floor_decal/grass_edge
	name = "grass edge"
	icon_state = "grass_edge"

/obj/effect/floor_decal/grass_edge/corner
	name = "grass edge"
	icon_state = "grass_edge_corner"

/obj/effect/floor_decal/plaque/yw
	name = "Commerative Plaque"
	icon = 'icons/obj/structures_yw32x32.dmi'
	icon_state = "plaque"
	desc = "A plaque commerating the building efforts of the sleepiest outpost in the sector, Yawn Wider."

/obj/effect/floor_decal/snow
	name = "snow"
	icon = 'icons/turf/overlays.dmi'
	icon_state = "snow"
/obj/effect/floor_decal/snow/floor
	icon_state = "snowfloor"
/obj/effect/floor_decal/snow/floor/edges
	icon_state = "snow_edges"
/obj/effect/floor_decal/snow/floor/edges2
	icon_state = "snow_edges2"
/obj/effect/floor_decal/snow/floor/edges3
	icon_state = "gravsnow_edges"
/obj/effect/floor_decal/snow/floor/surround
	icon_state = "snow_surround"

//Multi-part Floor Signs

/obj/effect/floor_decal/arrivals
	name = "arrivals sign"
	icon_state = "arrivals_1"

/obj/effect/floor_decal/arrivals/right
	icon_state = "arrivals_2"

/obj/effect/floor_decal/shuttles
	name = "departures sign"
	icon_state = "shuttle_1"

/obj/effect/floor_decal/shuttles/right
	icon_state = "shuttle_2"

/obj/effect/floor_decal/arrow
	name = "floor arrow"
	icon_state = "arrow_single"

/obj/effect/floor_decal/arrows
	name = "floor arrows"
	icon_state = "arrows"

//cetus plaques

/obj/effect/floor_decal/cetus/cetus1
	name = "cetus1"
	icon_state = "cetus1"

/obj/effect/floor_decal/cetus/cetus2
	name = "cetus2"
	icon_state = "cetus2"

/obj/effect/floor_decal/cetus/cetus3
	name = "cetus3"
	icon_state = "cetus3"

/obj/effect/floor_decal/cetus/cetus4
	name = "cetus4"
	icon_state = "cetus4"

/obj/effect/floor_decal/cetus/cetus5
	name = "cetus5"
	icon_state = "cetus5"

/obj/effect/floor_decal/cetus/cetus6
	name = "cetus6"
	icon_state = "cetus6"

/obj/effect/floor_decal/cetus/cetus7
	name = "cetus7"
	icon_state = "cetus7"

/obj/effect/floor_decal/cetus/cetus8
	name = "cetus8"
	icon_state = "cetus8"

/obj/effect/floor_decal/cetus/cetus9
	name = "cetus9"
	icon_state = "cetus9"

/obj/effect/floor_decal/cetus/andromeda1
	name = "andromeda1"
	icon_state = "andromeda1"

/obj/effect/floor_decal/cetus/andromeda2
	name = "andromeda2"
	icon_state = "andromeda2"

/obj/effect/floor_decal/cetus/andromeda3
	name = "andromeda3"
	icon_state = "andromeda3"

/obj/effect/floor_decal/cetus/andromeda4
	name = "andromeda4"
	icon_state = "andromeda4"

/obj/effect/floor_decal/cetus/andromeda5
	name = "andromeda5"
	icon_state = "andromeda5"

/obj/effect/floor_decal/cetus/andromeda6
	name = "andromeda6"
	icon_state = "andromeda6"


// === merged from flooring_decals_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/effect/floor_decal/stairs
	name = "stair decal"
	icon = 'icons/obj/decals_ch.dmi'
	icon_state = "metal_stairs"

/obj/effect/floor_decal/stairs/wood_stairs
	icon_state = "wood_stairs"

/obj/effect/floor_decal/stairs/wood_stairs2
	icon_state = "wood_stairs2"

/obj/effect/floor_decal/stairs/dark_stairs
	icon_state = "dark_stairs"


// === merged from flooring_decals_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/effect/floor_decal/flesh
	name = "flesh"
	icon = 'icons/turf/stomach_vr.dmi'
	icon_state = "flesh_floor_edges"

/obj/effect/floor_decal/flesh/colour
	name = "flesh"
	icon = 'icons/turf/stomach_vr.dmi'
	icon_state = "c_flesh_floor_edges"

/obj/effect/floor_decal/borderfloor/shifted
	icon_state = "borderfloor_shifted"

/obj/effect/floor_decal/borderfloorblack/shifted
	icon_state = "borderfloor_shifted"

/obj/effect/floor_decal/borderfloorwhite/shifted
	icon_state = "borderfloor_shifted"

/obj/effect/floor_decal/corner/beige/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/black/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/blue/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/brown/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/green/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/grey/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/lightgrey/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/lightorange
	name = "orange corner"
	color = "#ed983d"

/obj/effect/floor_decal/corner/lightorange/diagonal
	icon_state = "corner_white_diagonal"

/obj/effect/floor_decal/corner/lightorange/full
	icon_state = "corner_white_full"

/obj/effect/floor_decal/corner/lightorange/three_quarters
	icon_state = "corner_white_three_quarters"

/obj/effect/floor_decal/corner/lightorange/border
	icon_state = "bordercolor"

/obj/effect/floor_decal/corner/lightorange/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/lightorange/bordercorner
	icon_state = "bordercolorcorner"

/obj/effect/floor_decal/corner/lightorange/bordercorner2
	icon_state = "bordercolorcorner2"

/obj/effect/floor_decal/corner/lightorange/borderfull
	icon_state = "bordercolorfull"

/obj/effect/floor_decal/corner/lightorange/bordercee
	icon_state = "bordercolorcee"

/obj/effect/floor_decal/corner/lime/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/mauve/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/orange/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/paleblue/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/pink/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/purple/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/red/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/white/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/corner/yellow/border/shifted
	icon_state = "bordercolor_shifted"

/obj/effect/floor_decal/emblem/blu
	icon_state = "blu"
/obj/effect/floor_decal/emblem/blu_big
	icon_state = "blu_big"

/obj/effect/floor_decal/emblem/red
	icon_state = "red"
/obj/effect/floor_decal/emblem/red_big
	icon_state = "red_big"

/obj/effect/floor_decal/emblem/black
	icon_state = "black"
/obj/effect/floor_decal/emblem/black_big
	icon_state = "black_big"

/obj/effect/floor_decal/emblem/sword
	icon_state = "sword"
/obj/effect/floor_decal/emblem/sword_big
	icon_state = "sword_big"

/obj/effect/floor_decal/emblem/ark
	icon_state = "ark"
/obj/effect/floor_decal/emblem/ark_big
	icon_state = "ark_big"

/obj/effect/floor_decal/emblem/talon
	icon_state = "talon"
/obj/effect/floor_decal/emblem/talon_big
	icon_state = "talon_big"
/obj/effect/floor_decal/emblem/talon_big/center
	icon_state = "talon_center"

/obj/effect/floor_decal/emblem/itgdauntless
	icon_state = "itgdauntless"

/obj/effect/floor_decal/emblem/stellardelight
	icon_state = "stellar_delight"
/obj/effect/floor_decal/emblem/stellardelight/center
	icon_state = "stellar_delight_center"

/obj/effect/floor_decal/emblem/orangeline
	icon_state = "orange_line"

/obj/effect/floor_decal/emblem/aronai
	icon_state = "aronai"

/obj/effect/floor_decal/emblem/nt1
	icon_state = "nt1"
/obj/effect/floor_decal/emblem/nt2
	icon_state = "nt2"
/obj/effect/floor_decal/emblem/nt3
	icon_state = "nt3"

/obj/effect/floor_decal/milspec/stripe
	icon_state = "ms_plating_striped"
/obj/effect/floor_decal/milspec/hatchmarks
	icon_state = "ms_test_floor4"
/obj/effect/floor_decal/milspec/box
	icon_state = "ms_test_floor5"
/obj/effect/floor_decal/milspec/cargo
	icon_state = "ms_cargo"
/obj/effect/floor_decal/milspec/cargo_arrow
	icon_state = "ms_cargo_arrow"
/obj/effect/floor_decal/milspec/monotile
	icon_state = "ms_mono"

/obj/effect/floor_decal/milspec/color/blue
	icon_state = "ms_bluefull"
/obj/effect/floor_decal/milspec/color/blue/corner
	icon_state = "ms_bluecorner"
/obj/effect/floor_decal/milspec/color/blue/half
	icon_state = "ms_blue"
/obj/effect/floor_decal/milspec/color/red
	icon_state = "ms_redfull"
/obj/effect/floor_decal/milspec/color/red/corner
	icon_state = "ms_redcorner"
/obj/effect/floor_decal/milspec/color/red/half
	icon_state = "ms_red"
/obj/effect/floor_decal/milspec/color/purple
	icon_state = "ms_purplefull"
/obj/effect/floor_decal/milspec/color/purple/corner
	icon_state = "ms_purplecorner"
/obj/effect/floor_decal/milspec/color/purple/half
	icon_state = "ms_purple"
/obj/effect/floor_decal/milspec/color/emerald
	icon_state = "ms_emeraldfull"
/obj/effect/floor_decal/milspec/color/emerald/corner
	icon_state = "ms_emeraldcorner"
/obj/effect/floor_decal/milspec/color/emerald/half
	icon_state = "ms_emerald"
/obj/effect/floor_decal/milspec/color/orange
	icon_state = "ms_orangefull"
/obj/effect/floor_decal/milspec/color/orange/corner
	icon_state = "ms_orangecorner"
/obj/effect/floor_decal/milspec/color/orange/half
	icon_state = "ms_orange"
/obj/effect/floor_decal/milspec/color/green
	icon_state = "ms_greenfull"
/obj/effect/floor_decal/milspec/color/green/corner
	icon_state = "ms_greencorner"
/obj/effect/floor_decal/milspec/color/green/half
	icon_state = "ms_green"
/obj/effect/floor_decal/milspec/color/black
	icon_state = "ms_blackfull"
/obj/effect/floor_decal/milspec/color/black/corner
	icon_state = "ms_blackcorner"
/obj/effect/floor_decal/milspec/color/black/half
	icon_state = "ms_black"
/obj/effect/floor_decal/milspec/color/silver
	icon_state = "ms_silverfull"
/obj/effect/floor_decal/milspec/color/silver/corner
	icon_state = "ms_silvercorner"
/obj/effect/floor_decal/milspec/color/silver/half
	icon_state = "ms_silver"
/obj/effect/floor_decal/milspec/color/white
	icon_state = "ms_whitefull"
/obj/effect/floor_decal/milspec/color/white/corner
	icon_state = "ms_whitecorner"
/obj/effect/floor_decal/milspec/color/white/half
	icon_state = "ms_white"

/obj/effect/floor_decal/milspec_sterile/purple
	icon_state = "mss_purple"
/obj/effect/floor_decal/milspec_sterile/purple/corner
	icon_state = "mss_purple_corner"
/obj/effect/floor_decal/milspec_sterile/purple/half
	icon_state = "mss_purple_side"
/obj/effect/floor_decal/milspec_sterile/green
	icon_state = "mss_green"
/obj/effect/floor_decal/milspec_sterile/green/corner
	icon_state = "mss_green_corner"
/obj/effect/floor_decal/milspec_sterile/green/half
	icon_state = "mss_green_side"

//Shuttle Floor Decals
/obj/effect/floor_decal/shuttle
	name = "partial outline"
	icon_state = "semi_outline"
/obj/effect/floor_decal/shuttle/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/shuttle/grey
	color = "#545253"
/obj/effect/floor_decal/shuttle/blue
	color = "#00B8B2"

/obj/effect/floor_decal/shuttle/handicap
	name = "handicap marker"
	icon_state = "handicap"
/obj/effect/floor_decal/shuttle/handicap/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/shuttle/handicap/grey
	color = "#545253"

/obj/effect/floor_decal/shuttle/loading
	name = "loading/unloading marker"
	icon_state = "exit_and_entrance"
/obj/effect/floor_decal/shuttle/loading/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/shuttle/loading/grey
	color = "#545253"
/obj/effect/floor_decal/shuttle/loading/red
	color = "#a70000"

/obj/effect/floor_decal/shuttle/full_2
	name = "hatched marker"
	icon_state = "full_2"
/obj/effect/floor_decal/shuttle/full_2/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/shuttle/full_2/grey
	color = "#545253"
/obj/effect/floor_decal/shuttle/full_2/blue
	color = "#00B8B2"

//Industrial Floor Decals
/obj/effect/floor_decal/industrial/warning
	name = "hazard stripes"
	icon_state = "warning"
/obj/effect/floor_decal/industrial/warning/corner
	icon_state = "warningcorner"
/obj/effect/floor_decal/industrial/warning/full
	icon_state = "warningfull"
/obj/effect/floor_decal/industrial/warning/cee
	icon_state = "warningcee"
/obj/effect/floor_decal/industrial/warning/tile
	icon_state = "warningtile"

/obj/effect/floor_decal/industrial/warning/dust
	icon_state = "warning_dust"
/obj/effect/floor_decal/industrial/warning/dust/corner
	icon_state = "warningcorner_dust"
/obj/effect/floor_decal/industrial/warning/dust/full
	icon_state = "warningfull_dust"
/obj/effect/floor_decal/industrial/warning/dust/cee
	icon_state = "warningcee_dust"
/obj/effect/floor_decal/industrial/warning/dust/tile
	icon_state = "warningtile_dust"

/obj/effect/floor_decal/industrial/danger
	name = "danger stripes"
	icon_state = "danger"
/obj/effect/floor_decal/industrial/danger/corner
	icon_state = "dangercorner"
/obj/effect/floor_decal/industrial/danger/full
	icon_state = "dangerfull"
/obj/effect/floor_decal/industrial/danger/cee
	icon_state = "dangercee"

/obj/effect/floor_decal/industrial/hatch
	name = "hatched marking"
	icon_state = "delivery"
/obj/effect/floor_decal/industrial/hatch/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/hatch/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/hatch/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/hatch/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/rad_floor
	name = "radiation marking"
	icon_state = "rad_floor"
/obj/effect/floor_decal/industrial/rad_floor/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/rad_floor/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/rad_floor/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/rad_floor/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/outline
	name = "white outline"
	icon_state = "outline"
/obj/effect/floor_decal/industrial/outline/blue
	name = "blue outline"
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/outline/yellow
	name = "yellow outline"
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/outline/grey
	name = "grey outline"
	color = "#545253"
/obj/effect/floor_decal/industrial/outline/red
	name = "red outline"
	color = "#a70000"

/obj/effect/floor_decal/industrial/outline/cut_corners
	name = "white cut outline"
	icon_state = "cut_corners"
/obj/effect/floor_decal/industrial/outline/cut_corners/blue
	name = "blue cut outline"
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/outline/cut_corners/yellow
	name = "yellow cut outline"
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/outline/cut_corners/grey
	name = "grey cut outline"
	color = "#545253"
/obj/effect/floor_decal/industrial/outline/cut_corners/red
	name = "red cut outline"
	color = "#a70000"

/obj/effect/floor_decal/industrial/loading
	name = "loading area"
	icon_state = "loading"
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/loading/white
	color = null
/obj/effect/floor_decal/industrial/loading/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/loading/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/loading/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/arrows
	name = "tri-arrows"
	icon_state = "tri-arrows"
/obj/effect/floor_decal/industrial/arrows/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/arrows/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/arrows/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/arrows/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/caution
	name = "caution"
	icon_state = "caution"
/obj/effect/floor_decal/industrial/caution/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/caution/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/caution/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/caution/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/stand_clear
	name = "stand clear"
	icon_state = "stand_clear"
/obj/effect/floor_decal/industrial/stand_clear/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/stand_clear/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/stand_clear/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/stand_clear/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/bot_outline
	name = "bot outline"
	icon_state = "bot_outline"
/obj/effect/floor_decal/industrial/bot_outline/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/bot_outline/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/bot_outline/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/bot_outline/red
	color = "#a70000"

/obj/effect/floor_decal/industrial/bot_outline/corner
	icon_state = "bot_corners"
/obj/effect/floor_decal/industrial/bot_outline/corner/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/bot_outline/corner/blue
	color = "#00B8B2"
/obj/effect/floor_decal/industrial/bot_outline/corner/grey
	color = "#545253"
/obj/effect/floor_decal/industrial/bot_outline/corner/red
	color = "#a70000"

//Colored Warning Stripes
/obj/effect/floor_decal/industrial/warning/color
	icon_state = "warning_color"
/obj/effect/floor_decal/industrial/warning/color/corner
	icon_state = "warningcorner_color"
/obj/effect/floor_decal/industrial/warning/color/full
	icon_state = "warningfull_color"
/obj/effect/floor_decal/industrial/warning/color/cee
	icon_state = "warningcee_color"
/obj/effect/floor_decal/industrial/warning/color/tile
	icon_state = "warningtile_color"

/obj/effect/floor_decal/industrial/warning/color/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/warning/color/corner/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/warning/color/full/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/warning/color/cee/yellow
	color = "#CFCF55"
/obj/effect/floor_decal/industrial/warning/color/tile/yellow
	color = "#CFCF55"

/obj/effect/floor_decal/industrial/warning/color/red
	color = "#a70000"
/obj/effect/floor_decal/industrial/warning/color/corner/red
	color = "#a70000"
/obj/effect/floor_decal/industrial/warning/color/full/red
	color = "#a70000"
/obj/effect/floor_decal/industrial/warning/color/cee/red
	color = "#a70000"
/obj/effect/floor_decal/industrial/warning/color/tile/red
	color = "#a70000"

//Road markings

/obj/effect/floor_decal/road/center
	icon_state = "center_lines"
