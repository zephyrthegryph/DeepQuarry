/* This comment bypasses grep checks */ /var/__verdigris

/proc/__detect_verdigris()
	if (world.system_type == UNIX)
		return __verdigris = (fexists("./libverdigris.so") ? "./libverdigris.so" : "libverdigris")
	else
		return __verdigris = "verdigris"

#define VERDIGRIS (__verdigris || __detect_verdigris())
#define VERDIGRIS_CALL(name, args...) call_ext(VERDIGRIS, "byond:" + name)(args)

// The Rust exports are byondapi binds; byondapi's #[bind] macro suffixes the
// exported symbol with "_ffi" (e.g. fn verdigris_version -> verdigris_version_ffi).
/proc/verdigris_version()	return VERDIGRIS_CALL("verdigris_version_ffi")
/proc/verdigris_features()	return VERDIGRIS_CALL("verdigris_features_ffi")
/proc/verdigris_init()		return VERDIGRIS_CALL("verdigris_init_ffi")
/proc/verdigris_cleanup()	return VERDIGRIS_CALL("verdigris_cleanup_ffi")

// NOTE: verdigris bring-up (verdigris_init/cleanup + version log) lives in the real
// /world/New() in code/game/world.dm. A duplicate /world/New() here was silently
// discarded by the compiler (last-include-wins), so verdigris_init() never ran at boot.
