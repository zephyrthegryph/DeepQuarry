/proc/line_join()
    return {"alpha \
        beta"}
/proc/escaped_space()
    return "left\ right"
/proc/hex_bytes()
    return "\xFF\xD8\xFF"
/proc/hex_png()
    return "\x89PNG"
/proc/escaped_brackets()
    return "\[\]"
/proc/escaped_slash_empty_brackets()
    return "\\[]"
/proc/regex_like()
    return "a\\[]b"
