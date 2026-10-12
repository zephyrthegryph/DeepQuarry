var/global/selector_calls = 0
/proc/select_once()
    selector_calls += 1
    return 2

/proc/switch_throw()
    try
        switch(select_once())
            if(1)
                return "wrong"
            if(2)
                throw "selected"
            else
                return "default"
    catch(var/caught)
        return "[caught]:[selector_calls]"
    return "uncaught"
