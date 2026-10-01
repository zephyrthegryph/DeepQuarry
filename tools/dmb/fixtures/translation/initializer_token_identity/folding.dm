var/const/TOKEN_C = 2
/datum/token_target
/obj/fold
    var/list/fold_a = list(1+1)
    var/list/fold_b = list(2)
    var/list/fold_c = list(TOKEN_C)
    var/list/assoc_a = list(a=1)
    var/list/assoc_b = list("a"=1)
    var/list/assoc_c = list(1,"a")
    var/sound/sound_a = sound()
    var/sound/sound_b = sound(null)
    var/sound/sound_c = sound(null,0)
    var/sound/sound_d = sound(null,0,0,0,100)
    var/sound/sound_e = sound(file=null,repeat=0)
    var/datum/token_target/new_a = new /datum/token_target(1+1)
    var/datum/token_target/new_b = new /datum/token_target(2)
    var/datum/token_target/new_c = new /datum/token_target(TOKEN_C)
