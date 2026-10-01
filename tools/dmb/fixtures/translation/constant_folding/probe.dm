/var/const/global_scale = 2 + 3 * 4
/var/const/global_mask = (1 << 5) | 3
/var/const/global_label = "DM" + " compiler"
/var/global/global_copy = global_scale * 2
/world
    name = "Fold" + " probe"
    fps = 10 * 3
    view = 2 + 5
/datum/fold_probe
    var/const/local_scale = global_scale + 1
    var/const/local_mask = ~3 & 255
    var/const/choice = 0 ? 20 : 30
    var/const/modulo = 11 % 3
    var/const/negative = -5 >> 1
    var/const/power = 2 ** 3
    var/const/logical_and = 5 && 2
    var/const/logical_or = 5 || 2
    var/const/hex = 0xFF & 0x0F
    var/value = local_scale + global_scale
/datum/fold_probe/child
    var/const/inherited = local_scale * 3
/obj/fold_probe
    name = "Fold" + " object"
    density = 1 << 0
    mouse_opacity = 1 + 1
