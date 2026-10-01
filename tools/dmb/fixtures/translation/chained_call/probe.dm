/proc/dynamic_call(target)
    return call(target, "foo")(1)
/proc/external_call(library)
    return call_ext(library, "bar")(2)
