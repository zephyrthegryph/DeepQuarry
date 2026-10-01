/proc/switch_trailing_null(var/value)
    switch(value)
        if("a")
            return 1
        if("b", null)
            return 2
        else
            return 3
