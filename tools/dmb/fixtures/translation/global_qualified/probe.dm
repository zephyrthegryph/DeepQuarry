/var/foo = 1
/proc/probe_read()
    return global.foo
/proc/probe_write()
    global.foo = 2
