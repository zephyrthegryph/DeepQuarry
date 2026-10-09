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

DECLARE_SHARED_CACHE(crayon_art, GLOBAL_PROC_REF(build_crayon_art), SC_NEVER)

/// Builder for crayon_art: the design `art_type` in `art_color`, and its shading in `art_shade`, as the two layers a decal shows.
/proc/build_crayon_art(art_type, art_color, art_shade)
	var/icon/mainOverlay = new/icon('icons/effects/crayondecal.dmi',"[art_type]",2.1)
	var/icon/shadeOverlay = new/icon('icons/effects/crayondecal.dmi',"[art_type]s",2.1)
	mainOverlay.Blend(art_color,ICON_ADD)
	shadeOverlay.Blend(art_shade,ICON_ADD)
	return list(image(mainOverlay), image(shadeOverlay))

/// The drawing in its colour and its shade, then the janitor HUD's mark.
/obj/effect/decal/cleanable/crayon/cleanable_look(datum/look/look)
	var/list/art = CACHED_KEY(crayon_art, "[art_type]|[art_color]|[art_shade]", art_type, art_color, art_shade)
	look.overlay(art[1])
	look.overlay(art[2])
	janitor_hud(look)
