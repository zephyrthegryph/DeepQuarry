/proc/range_first_null(var/value)
    switch(value)
        if(-10 to -0.1)
            return "negative"
        if(null)
            return "null"
        if(0)
            return "zero"
        if("text")
            return "text"
        else
            return "other"
