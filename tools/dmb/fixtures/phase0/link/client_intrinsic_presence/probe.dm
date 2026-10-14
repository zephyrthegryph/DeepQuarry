/client
    parent_type = /datum
    preload_rsc = 0
    control_freak = 0
    show_verb_panel = 0
/client/proc/probe_preload(value)
    src.preload_rsc = value
    return src.preload_rsc
/client/proc/probe_control(value)
    src.control_freak = value
    return src.control_freak
/client/proc/probe_panel(value)
    src.show_verb_panel = value
    return src.show_verb_panel
