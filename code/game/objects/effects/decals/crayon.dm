/obj/effect/decal/cleanable/crayon
	name = "rune"
	desc = "A rune drawn in crayon."
	icon = 'icons/obj/rune.dmi'
	plane = DIRTY_PLANE
	layer = DIRTY_LAYER
	anchored = TRUE
	var/art_type
	var/art_color
	var/art_shade

CAPABILITIES(/obj/effect/decal/cleanable/crayon)
	param(nameof(art_color), pos = 1, default = "#FFFFFF")
	param(nameof(art_shade), pos = 2, default = "#000000")
	param(nameof(drawing_kind), pos = 3, apply = PROC_REF(draw_kind))
	param(nameof(age), pos = 4)

/// What was drawn (its constructor param): a rune or graffiti picks its design.
/obj/effect/decal/cleanable/crayon/var/drawing_kind = "rune"

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/decal/cleanable/crayon/proc/draw_kind(kind)
	name = kind
	desc = "A [kind] drawn in crayon."
	switch(kind)
		if("rune")
			kind = "rune[rand(1,6)]"
		if("graffiti")
			kind = pick("amyjon","face","matt","revolution","engie","guy","end","dwarf","uboa")
	art_type = kind

DECLARE_APPEARANCE_PROC(/obj/effect/decal/cleanable/crayon, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/effect/decal/cleanable/crayon/appearance_overlays()
	. = list()
	var/icon/mainOverlay = new/icon('icons/effects/crayondecal.dmi',"[art_type]",2.1)
	var/icon/shadeOverlay = new/icon('icons/effects/crayondecal.dmi',"[art_type]s",2.1)

	if(mainOverlay && shadeOverlay)
		mainOverlay.Blend(art_color,ICON_ADD)
		shadeOverlay.Blend(art_shade,ICON_ADD)

		. += mainOverlay
		. += shadeOverlay

	. += add_janitor_hud_overlay()
	return .
