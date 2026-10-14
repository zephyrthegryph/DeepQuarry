var/global/library_name

/proc/detect_library()
    return library_name = world.params["library"]

/proc/static_binding()
    var/static/function_handle = load_ext((library_name || detect_library()), "byond:verdigris_init_ffi")
    return function_handle

/world/New()
    ..()
    var/direct_handle = load_ext(world.params["library"], "byond:verdigris_init_ffi")
    world.log << "DQ_FFI direct [!isnull(direct_handle)]"
    world.log << "DQ_FFI direct_abi [call_ext(direct_handle)("57759af855de3189")]"
    var/static_handle = static_binding()
    world.log << "DQ_FFI static [!isnull(static_handle)]"
    world.log << "DQ_FFI static_abi [call_ext(static_handle)("57759af855de3189")]"
    world.log << "DQ_FFI finished"
    shutdown()
