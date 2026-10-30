
/**
 * Called when an atom is created in byond (built in engine proc)
 *
 * Not a lot happens here in SS13 code, as we offload most of the work to the
 * [Initialization][/atom/proc/Initialize] proc, mostly we run the preloader
 * if the preloader is being used and then call [InitAtom][/datum/system/atoms/proc/InitAtom] of which the ultimate
 * result is that the Initialize proc is called.
 *
 */
/atom/New(loc, ...)
	//atom creation method that preloads variables at creation
	if(GLOB.use_preloader && src.type == GLOB._preloader_path)//in case the instantiated atom is creating other atoms in New()
		world.preloader_load(src)

	// make() records and param(pos =) arguments write the instance's params before anything of the type runs (code/engine/lifeforms/params.dm).
	var/list/init_args = args
	if(length(args) > 1 && lifeform_new_args(src, args))
		init_args = args.Copy()
		init_args.Cut(2, 3) // the make() record is not an Initialize() argument
	if(ismob(src))
		profiles_build(src) // its profile records exist before its init writes them (code/engine/declare/profiles.dm)
	var/do_initialize = atoms_atom_initialized()
	if(do_initialize != INITIALIZATION_INSSATOMS)
		init_args[1] = do_initialize == INITIALIZATION_INNEW_MAPLOAD
		if(SSatoms.InitAtom(src, FALSE, init_args))
			//we were deleted
			return

/**
 * The primary method that objects are setup in SS13 with
 *
 * we don't use New as we have better control over when this is called and we can choose
 * to delay calls or hook other logic in and so forth
 *
 * During roundstart map parsing, atoms are queued for initialization in the base atom/New(),
 * After the map has loaded, then Initialize is called on all atoms one by one. NB: this
 * is also true for loading map templates as well, so they don't Initialize until all objects
 * in the map file are parsed and present in the world
 *
 * If you're creating an object at any point after SSInit has run then this proc will be
 * immediately be called from New.
 *
 * mapload: This parameter is true if the atom being loaded is either being initialized during
 * the Atom subsystem initialization, or if the atom is being loaded from the map template.
 * If the item is being created at runtime any time after the Atom subsystem is initialized then
 * it's false.
 *
 * The mapload argument occupies the same position as loc when Initialize() is called by New().
 * loc will no longer be needed after it passed New(), and thus it is being overwritten
 * with mapload at the end of atom/New() before this proc (atom/Initialize()) is called.
 *
 * You must always call the parent of this proc, otherwise failures will occur as the item
 * will not be seen as initialized (this can lead to all sorts of strange behaviour, like
 * the item being completely unclickable)
 *
 * You must not sleep in this proc, or any subprocs
 *
 * Any parameters from new are passed through (excluding loc), naturally if you're loading from a map
 * there are no other arguments
 *
 * Must return an [initialization hint][INITIALIZE_HINT_NORMAL] or a runtime will occur.
 *
 * Note: the following functions don't call the base for optimization and must copypasta handling:
 * * [/turf/proc/Initialize]
 * * [/turf/open/space/proc/Initialize]
 */
/atom/proc/Initialize(mapload, ...)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_CALL_PARENT(TRUE)

	if(flags & ATOM_INITIALIZED)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	flags |= ATOM_INITIALIZED
	// set /tg/'s INITIALIZED_1 in parallel with CHOMP's ATOM_INITIALIZED so
	// LINDA's `flags_1 & INITIALIZED_1` checks (SSair.add_to_active, signal-handler
	// gates, /tg/ component lifecycle) work without us having to rewrite each
	// callsite to use the CHOMP flag.
	flags_1 |= INITIALIZED_1

	//atom color stuff
	if(color)
		add_atom_colour(color, FIXED_COLOUR_PRIORITY)

	if(uses_integrity)
		atom_integrity = max_integrity

	// Declared instance state (code/datums/lifecycle/declarations.dm): children, gas, reagents,
	// appearance. Here, at the root of the chain, so a subtype's code after `. = ..()` sees it.
	BOOT_PHASE_BEGIN(bp_decls)
	lifecycle_decls_init(src, mapload)
	BOOT_PHASE_END(bp_decls, "lifecycle_decls_init" + BOOT_KIND(src), src)
	// Capabilities' per-instance state, then the first look (code/datums/capabilities/).
	BOOT_PHASE_BEGIN(bp_caps)
	caps_init(src, mapload)
	BOOT_PHASE_END(bp_caps, "caps_init" + BOOT_KIND(src), src)

	/*
	if (atom_rules_of(src).light_system == COMPLEX_LIGHT && glow_of(src).power && glow_of(src).range)
		update_light()
	*/
	return INITIALIZE_HINT_NORMAL

/// Whether `A` has begun its Initialize(): the lifecycle bit the initializer sets once. A draw that must not run before it asks here (PROC_SUMMARY: the
/// bit is set once and never cleared, and the first refresh is queued as the initializer finishes, so nothing needs to subscribe).
PROC_SUMMARY(/proc/atom_initialized)
/proc/atom_initialized(atom/A)
	return !!(A.flags & ATOM_INITIALIZED)
