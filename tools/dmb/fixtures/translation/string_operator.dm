/datum/stringable
    proc/operator""()
        return "custom"
/proc/string_operator(datum/stringable/X)
    return "[X]"