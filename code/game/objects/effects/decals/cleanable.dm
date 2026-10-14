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
	/// Which of the janitor HUD's marks it shows (1 to 9), rolled when it is made.
	var/hud_variant = 1

	///The type of cleaning required to clean the decal, CLEAN_TYPE_LIGHT_DECAL can be cleaned with mops and soap, CLEAN_TYPE_HARD_DECAL can be cleaned by soap, see __DEFINES/cleaning.dm for the others
	var/clean_type = CLEAN_TYPE_LIGHT_DECAL

CAPABILITIES(/obj/effect/decal/cleanable)
	owns_many(nameof(viruses), /datum/affliction/contagion)
	param(nameof(age), pos = 1, apply = PROC_REF(age_or_contagions))
	rolls(nameof(icon_state), PROC_REF(roll_icon_state), when = nameof(random_icon_states))
	rolls(nameof(hud_variant), range_of(1, 9))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A vomit made with contagions carries them (new /obj/effect/decal/cleanable/vomit(loc, contagion_copies(...))).
/obj/effect/decal/cleanable/proc/age_or_contagions(given)
	if(islist(given))
		add_contagions(given, copy = FALSE)
		age = initial(age)

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): one of the filth's looks.
/obj/effect/decal/cleanable/proc/roll_icon_state(datum/roller/R)
	return length(random_icon_states) ? R.choose(random_icon_states) : icon_state

// ALLOW(init/INSTANCE_STATE): filth not loaded with the map is tracked for persistence
/obj/effect/decal/cleanable/Initialize(mapload)
	if(!mapload || !CONFIG_GET(flag/persistence_ignore_mapload))
		SSpersistence.track_value(src, /datum/persistent/filth)
	return ..()

/// Adopts `contagions` into viruses as private copies. copy = FALSE when they are fresh unowned
/// copies (contagion_copies()); a contagion some other holder owns is always copied, so a splat
/// never aliases (or mutates) its source's contagions.
/obj/effect/decal/cleanable/proc/add_contagions(list/contagions, copy = TRUE)
	for(var/datum/affliction/contagion/D in contagions)
		rel_add(src, nameof(viruses), (copy || owner_of(D)) ? D.Copy() : D)

/obj/effect/decal/cleanable/wash(clean_types)
	. = ..()
	if (. || (clean_types & clean_type))
		consume(src)
		return TRUE

// persistent filth forgets this decal.
/obj/effect/decal/cleanable/lifecycle_dematerialize()
	SSpersistence.forget_value(src, /datum/persistent/filth)
	..()

DECLARE_SHARED_CACHE(janitor_hud_images, GLOBAL_PROC_REF(build_janitor_hud_image), SC_NEVER)

/// Builder for janitor_hud_images: the janitor HUD's mark `variant`.
/proc/build_janitor_hud_image(variant)
	// This was original a seperate object that followed the grime, it got stuck in everything you can imagine!
	// It also likely doubled the memory use of every cleanable decal on station...
	var/image/hud = image('icons/mob/hud.dmi', icon_state = "janhud[variant]")
	hud.appearance_flags = (RESET_COLOR|PIXEL_SCALE|KEEP_APART)
	hud.plane = PLANE_JANHUD
	hud.layer = BELOW_MOB_LAYER
	hud.mouse_opacity = 0
	//HUD VARIANT: Allows the hud to show up with it's normal alpha, even if the 'dirty thing' it's attached to has a low alpha (ex: dirt). If you want to disable it, simply comment out the lines between the 'HUD VARIANT' tag!
	//hud.appearance_flags = RESET_ALPHA | RESET_COLOR
	//hud.alpha = 255
	//HUD VARIANT end
	return hud

/obj/effect/decal/cleanable/draw(datum/look/look)
	..()
	cleanable_look(look)

/// What the decal looks like. A subtype replaces it entirely (and ends with janitor_hud()) rather than extending it.
/obj/effect/decal/cleanable/proc/cleanable_look(datum/look/look)
	janitor_hud(look)

/// The janitor HUD's mark on the decal.
/obj/effect/decal/cleanable/proc/janitor_hud(datum/look/look)
	look.overlay(CACHED_KEY(janitor_hud_images, "[hud_variant]", hud_variant))

// Contagion datums are shared (copied lists, one disease spread across many decals), never owned here.
