// The emissive blocker: the layer a movable carries so its sprite blocks light that glows through it from behind. It is a priority
// overlay (it must sit above every layer a look draws), and it is the only overlay a movable keeps outside the look builder, so
// the raw overlay writes live in this engine file (dx_raw_overlays exempts it by path, tools/ci/lint_scopes.toml).

#if EMISSIVE_BLOCK_GENERIC != 0
	#error EMISSIVE_BLOCK_GENERIC is expected to be 0 to facilitate a weird optimization hack where we rely on it being the most common.
	#error Read the comment above blocks_emissive in code/__defines/lighting.dm for details.
#endif

/// Puts the blocker on a movable that is being initialized: nothing for a type that blocks none, the shared generic overlay for
/// EMISSIVE_BLOCK_GENERIC, an owned blocker object (watched, so a blocker deleted from outside is dropped) for EMISSIVE_BLOCK_UNIQUE.
/atom/movable/proc/emissive_blocker_attach()
	if(lighting_of(src).emissive)
		if(lighting_of(src).emissive == EMISSIVE_BLOCK_UNIQUE)
			render_target = ref(src)
			rel_set(src, nameof(/atom/movable::em_block), new /atom/movable/emissive_blocker(null, src))
			add_overlay(list(em_block), TRUE)
			observe(em_block, /datum/notice/qdeleting, src, then(PROC_REF(emblocker_gc)))
	else
		var/mutable_appearance/gen_emissive_blocker = mutable_appearance(icon, icon_state, plane = PLANE_EMISSIVE, alpha = src.alpha)
		gen_emissive_blocker.color = GLOB.em_block_color
		gen_emissive_blocker.dir = dir
		gen_emissive_blocker.appearance_flags |= appearance_flags
		add_overlay(list(gen_emissive_blocker), TRUE)

/// Takes the unique blocker off in the destroy transaction (the generic overlay dies with the movable).
/atom/movable/proc/emissive_blocker_detach()
	if(em_block)
		cut_overlay(em_block)
		unobserve(em_block, /datum/notice/qdeleting, src)
		rel_clear(src, nameof(em_block))

/atom/movable/proc/emblocker_gc(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = N.target
	unobserve(source, /datum/notice/qdeleting, src)
	cut_overlay(source)
	// A blocker deleted from outside leaves em_block in its destroy's phase 2.
