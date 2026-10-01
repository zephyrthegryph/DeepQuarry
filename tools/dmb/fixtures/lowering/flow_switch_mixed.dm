/proc/flow_switch_mixed(value)
    switch(value)
        if(20)
            return 500
        if(136 | 1)
            return 1
        if(/datum, /mob)
            return 300
        if("word", null)
            return 4
    return 0
/proc/flow_switch_type_first(value)
    switch(value)
        if(/datum, /mob)
            return 1
        if(1 to 3)
            return 2
        if(10, "word", null)
            return 3
    return 0
/proc/flow_switch_string_first(value)
    switch(value)
        if("word")
            return 1
        if(10, /datum, null)
            return 2
    return 0
/proc/flow_switch_range_first(value)
    switch(value)
        if(1 to 3)
            return 1
        if("word", /datum, null)
            return 2
    return 0
