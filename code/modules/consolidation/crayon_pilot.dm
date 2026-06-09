// Crayon consolidation pilot.
// Demonstrates: collapse N nearly-identical subtypes into one parameterized
// parent + a variant registry, to remove the per-type init-table cost
// (~12.5 KB per subtype on this codebase).
//
// Before: 13 plain-color subtypes (crayon: red/orange/yellow/green/blue/purple,
//         marker: black/red/orange/yellow/green/blue/purple) each living in
//         crayons.dm with name/icon_state/color overrides only.
// After:  the 13 subtypes are gone; the two parent types (/obj/item/pen/crayon
//         and /obj/item/pen/crayon/marker) accept a `variant` arg in
//         Initialize and configure themselves from a static registry.
//
// Special variants (mime, rainbow) are KEPT as separate subtypes because they
// override attack_self with unique behavior.

// Per-family variant tables: variant_name -> list("colour", "shadeColour", "icon_state")
GLOBAL_LIST_INIT(dq_crayon_variants, list(
	"red"    = list("#DA0000", "#810C0C", "crayonred"),
	"orange" = list("#FF9300", "#A55403", "crayonorange"),
	"yellow" = list("#FFF200", "#886422", "crayonyellow"),
	"green"  = list("#A8E61D", "#61840F", "crayongreen"),
	"blue"   = list("#00B7EF", "#0082A8", "crayonblue"),
	"purple" = list("#DA00FF", "#810CFF", "crayonpurple"),
))

GLOBAL_LIST_INIT(dq_marker_variants, list(
	"black"  = list("#2D2D2D", "#000000", "markerblack"),
	"red"    = list("#DA0000", "#810C0C", "markerred"),
	"orange" = list("#FF9300", "#A55403", "markerorange"),
	"yellow" = list("#FFF200", "#886422", "markeryellow"),
	"green"  = list("#A8E61D", "#61840F", "markergreen"),
	"blue"   = list("#00B7EF", "#0082A8", "markerblue"),
	"purple" = list("#DA00FF", "#810CFF", "markerpurple"),
))

// Re-open the crayon parent to accept a variant arg.
// Existing /obj/item/pen/crayon/Initialize sets `name = "[colourName] [name]"`,
// which still works once variant has populated colourName. The `variant` var
// is now declared on /obj/item (see gear_tweak_variant.dm); we just override
// apply_variant() per family.
/obj/item/pen/crayon/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/pen/crayon/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_crayon_variants[variant]
	if(!v)
		return
	colour = v[1]
	shadeColour = v[2]
	icon_state = v[3]
	colourName = variant

/obj/item/pen/crayon/marker/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_marker_variants[variant]
	if(!v)
		return
	colour = v[1]
	shadeColour = v[2]
	icon_state = v[3]
	colourName = variant
