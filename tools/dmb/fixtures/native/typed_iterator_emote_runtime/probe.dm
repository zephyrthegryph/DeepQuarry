// Independent receiver/iterator controls. Capture BYOND before assigning goldens.
/obj/emote_target
    var/marker = 17
/obj/emote_target/proc/see_emote(mob/source, message, mode)
    return marker + mode
/atom/movable/screen/emote_foreign
    var/marker = 91
/mob/emote_source/proc/dispatch(list/viewers)
    var/total = 0
    for(var/obj/emote_target/O as anything in viewers)
        if(O)
            var/final_message = "message"
            if(client && O && !(z == O.z))
                final_message = "other"
            total += O.see_emote(src, final_message, 2)
    return total
/proc/filtered_count(list/viewers)
    var/count = 0
    for(var/obj/O in viewers)
        count++
    return count
/proc/unfiltered_count(list/viewers)
    var/count = 0
    for(var/obj/O as anything in viewers)
        count++
    return count
/proc/filtered_dispatch(list/viewers)
    var/total = 0
    for(var/obj/emote_target/O in viewers)
        total += O.see_emote(null, "message", 2)
    return total
/world/New()
    ..()
    var/obj/emote_target/A = new
    var/obj/emote_target/B = new
    B.marker = 23
    var/atom/movable/screen/emote_foreign/F = new
    var/atom/movable/plain = new
    var/mob/emote_source/S = new
    var/list/objects = list(A, B)
    var/list/mixed = list(F, A, B)
    world.log << "DQ_ITER objects [S.dispatch(objects)]"
    world.log << "DQ_ITER filtered_count [filtered_count(mixed)]"
    world.log << "DQ_ITER unfiltered_count [unfiltered_count(mixed)]"
    world.log << "DQ_ITER filtered_dispatch [filtered_dispatch(mixed)]"
    world.log << "DQ_ITER obj_isobj [isobj(A)]"
    world.log << "DQ_ITER screen_isobj [isobj(F)]"
    world.log << "DQ_ITER movable_isobj [isobj(plain)]"
    world.log << "DQ_ITER obj_strict [istype(A, /obj)]"
    world.log << "DQ_ITER screen_strict [istype(F, /obj)]"
    world.log << "DQ_ITER movable_strict [istype(plain, /obj)]"
    world.log << "DQ_ITER obj_type [A.type]"
    world.log << "DQ_ITER screen_type [F.type]"
    world.log << "DQ_ITER movable_type [plain.type]"
    var/list/all_movable = list(F, plain, A, B)
    world.log << "DQ_ITER all_filtered_count [filtered_count(all_movable)]"
    var/caught = 0
    try
        S.dispatch(mixed)
    catch(var/exception/error)
        caught = 1
    world.log << "DQ_ITER mixed_caught [caught]"
    world.log << "DQ_ITER finished"
    shutdown()
