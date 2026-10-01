/proc/foo(var/x)
    return x + 1
/proc/dynamic_call_path_test()
    return call("/proc/foo")(4)
