/datum/dispatch_base
    proc/plain_method()
        return 11
    proc/under_score()
        return 13
    proc/custom_method()
        set name = "Custom Display"
        return 17
/datum/dispatch_base/child

/world/New()
    ..()
    var/datum/dispatch_base/child/D = new
    var/plain_source = call(D, "plain_method")()
    var/plain_display = call(D, "plain method")()
    var/inherited_source = call(D, "under_score")()
    var/inherited_display = call(D, "under score")()
    var/custom_source = call(D, "custom_method")()
    var/custom_display = call(D, "Custom Display")()
    world.log << "DISPATCH [plain_source] [plain_display] [inherited_source] [inherited_display] [custom_source] [custom_display]"
    del(world)
