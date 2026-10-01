/datum/stringable
    proc/operator""()
        return "custom"
/proc/string_any(X)
    return "[X]"
/proc/string_datum(datum/X)
    return "[X]"
/proc/string_custom(datum/stringable/X)
    return "[X]"
/proc/string_atom(atom/X)
    return "[X]"
/proc/string_custom_article(datum/stringable/X)
    return "\the [X]"
/proc/string_atom_article(atom/X)
    return "\the [X]"
/proc/string_prefix(X)
    return "K[X]"
/proc/string_suffix(X)
    return "[X]K"
/proc/string_double(X)
    return "[X][X]"

/proc/string_space(X)
    return " [X]K0"
/proc/string_newline(X)
    return "\n[X]K0"
/proc/string_proper(X)
    return "\proper [X]K0"
/proc/string_improper(X)
    return "\improper [X]K0"
/proc/string_the(X)
    return "\the [X]K0"
/proc/string_The(X)
    return "\The [X]K0"
