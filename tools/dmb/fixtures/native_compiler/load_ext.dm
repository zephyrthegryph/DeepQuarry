/proc/load_function(library, function)
    return load_ext(library, function)
/proc/invoke_function(function, value)
    return call_ext(function)(value)
/proc/invoke_list(function, list/values)
    return call_ext(function)(arglist(values))
/world/New()
    var/function = load_ext(world.params["library"], "byond:verdigris_version_ffi")
    world.log << "LOAD_EXT [!isnull(function)] [call_ext(function)()]"
    del(world)



