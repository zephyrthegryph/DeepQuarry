/proc/shared_ui()
    return list(interface("Bundle"), ui_shape(state = enum(list("off", "on"))), op("bundle-key", inputs(hand(), ui_act("toggle", arg("value", bool())))))
/proc/nested_ui()
    return list(shared_ui(), ui_shape(extra = list_of(schema_text(8))))
/proc/not_bundle()
    var/x = 1
    return list(interface("Ignored"), ui_shape(x = int()))
