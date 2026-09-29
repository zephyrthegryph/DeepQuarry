/*
USAGE NOTE
For decals, the var Persistent = 'has already been saved', and is primarily used to prevent duplicate savings of generic filth (filth.dm).
This also means 'TRUE' can be used to define a decal as "Do not save at all, even as a generic replacement." if a dirt decal is considered 'too common' to save.
generic_filth = TRUE means when the decal is saved, it will be switched out for a generic green 'filth' decal.
*/

/obj/effect/decal/cleanable
	plane = DIRTY_PLANE
	layer = DIRTY_LAYER
	var/persistent = FALSE
	/// Diseases carried in it (blood, mucus, vomit), passed on by touch. Owned private copies:
	/// never a mob's own contagion (add_contagions() copies anything another holder owns).
	var/list/datum/affliction/contagion/viruses
	var/generic_filth = FALSE
	var/age = 0
	var/list/random_icon_states

	///The type of cleaning required to clean the decal, CLEAN_TYPE_LIGHT_DECAL can be cleaned with mops and soap, CLEAN_TYPE_HARD_DECAL can be cleaned by soap, see __DEFINES/cleaning.dm for the others
	var/clean_type = CLEAN_TYPE_LIGHT_DECAL

/obj/effect/decal/cleanable/Initialize(mapload, _age)
	if(islist(_age)) // new /obj/effect/decal/cleanable/vomit(loc, contagion_copies(...))
		add_contagions(_age, copy = FALSE)
	else if(!isnull(_age))
		age = _age
	if(random_icon_states && length(src.random_icon_states) > 0)
		src.icon_state = DEFAULTPICK(src.random_icon_states, null)
	if(!mapload || !CONFIG_GET(flag/persistence_ignore_mapload))
		SSpersistence.track_value(src, /datum/persistent/filth)
	. = ..()
	update_icon()

/// Adopts `contagions` into viruses as private copies. copy = FALSE when they are fresh unowned
/// copies (contagion_copies()); a contagion some other holder owns is always copied, so a splat
/// never aliases (or mutates) its source's contagions.
/obj/effect/decal/cleanable/proc/add_contagions(list/contagions, copy = TRUE)
	for(var/datum/affliction/contagion/D in contagions)
		own_add(src, "viruses", (copy || owner_of(D)) ? D.Copy() : D)

/obj/effect/decal/cleanable/wash(clean_types)
	. = ..()
	if (. || (clean_types & clean_type))
		qdel(src)
		return TRUE

// persistent filth forgets this decal.
/obj/effect/decal/cleanable/lifecycle_dematerialize()
	SSpersistence.forget_value(src, /datum/persistent/filth)
	..()

DECLARE_APPEARANCE_PROC(/obj/effect/decal/cleanable, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/effect/decal/cleanable/appearance_overlays()
	. = list()
	// Overrides should not inheret from this, and instead replace it entirely to match this in some form.
	// add_janitor_hud_overlay() does not pre-cut overlays, so cut_overlays() must be called first.
	// This is so it may be used with update_icon() overrides that use overlays, while adding the janitor overlay at the end.
	. += add_janitor_hud_overlay()

/obj/effect/decal/cleanable/proc/add_janitor_hud_overlay()
	. = list()
	// This was original a seperate object that followed the grime, it got stuck in everything you can imagine!
	// It also likely doubled the memory use of every cleanable decal on station...
	var/image/hud = image('icons/mob/hud.dmi', src, "janhud[rand(1,9)]")
	hud.appearance_flags = (RESET_COLOR|PIXEL_SCALE|KEEP_APART)
	hud.plane = PLANE_JANHUD
	hud.layer = BELOW_MOB_LAYER
	hud.mouse_opacity = 0
	//HUD VARIANT: Allows the hud to show up with it's normal alpha, even if the 'dirty thing' it's attached to has a low alpha (ex: dirt). If you want to disable it, simply comment out the lines between the 'HUD VARIANT' tag!
	//hud.appearance_flags = RESET_ALPHA | RESET_COLOR
	//hud.alpha = 255
	//HUD VARIANT end
	. += hud

// Contagion datums are shared (copied lists, one disease spread across many decals), never owned here.
