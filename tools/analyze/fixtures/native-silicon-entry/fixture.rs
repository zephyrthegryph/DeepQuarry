pub const DEFINES:&str="#define issilicon(A) istype(A, /mob/living/silicon)\n#define isAI(A) istype(A, /mob/living/silicon/ai)\n#define isrobot(A) istype(A, /mob/living/silicon/robot)\n#define ispAI(A) istype(A, /mob/living/silicon/pai)\n";
pub const TYPES:&str="/datum/act\n    var/actor\n/datum/act/op\n/datum/act/timer\n/datum/prompt/choice\n/mob/living/silicon/ai\n/mob/living/silicon/robot\n/obj/machinery\n";
pub const CASES:&[(&str,&str)]=&[
 ("direct_macro","/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n"),
 ("macro_other_actor","/obj/machinery/proc/use(datum/act/op/A,mob/other)\n    return isrobot(other)\n"),
 ("literal_actor","/obj/machinery/proc/use(datum/act/op/A)\n    return istype(A.actor,/mob/living/silicon/ai)\n"),
 ("local_actor","/obj/machinery/proc/use(datum/act/op/A)\n    var/mob/user=A.actor\n    return istype(user,/mob/living/silicon/robot)\n"),
 ("flow_insensitive","/obj/machinery/proc/use(datum/act/op/A)\n    return istype(user,/mob/living/silicon/robot)\n    var/mob/user=A.actor\n"),
 ("ternary_actor","/obj/machinery/proc/use(datum/act/op/A)\n    var/mob/user=A.actor ? null : A.actor\n    return istype(user,/mob/living/silicon/robot)\n"),
 ("act_alias","/obj/machinery/proc/use(datum/act/op/A)\n    var/X=A\n    var/user=X.actor\n    return istype(user,/mob/living/silicon)\n"),
 ("helper","/obj/machinery/proc/use(datum/act/op/A)\n    return helper(A.actor)\n/obj/machinery/proc/helper(mob/user)\n    return isrobot(user)\n"),
 ("act_helper","/obj/machinery/proc/use(datum/act/op/A)\n    return helper(A)\n/obj/machinery/proc/helper(X)\n    return istype(X.actor,/mob/living/silicon)\n"),
 ("mixed_timer","/obj/machinery/proc/use(datum/act/op/A,datum/act/timer/T)\n    return isAI(A.actor)\n"),
 ("prompt_prepare","/datum/prompt/choice/prepare(datum/act/op/A)\n    return isAI(A.actor)\n"),
 ("base_prompt_prepare","/datum/prompt/proc/prepare(datum/act/op/A)\n    return isAI(A.actor)\n"),
 ("other_mob","/obj/machinery/proc/use(datum/act/op/A,mob/other)\n    return helper(other)\n/obj/machinery/proc/helper(mob/M)\n    return isAI(M)\n"),
 ("helper_handler_skipped","/obj/machinery/proc/use(datum/act/op/A)\n    return helper(A)\n/obj/machinery/proc/helper(datum/act/op/X)\n    return isAI(X.actor)\n"),
 ("global","/obj/machinery/proc/use(datum/act/op/A)\n    return global_helper(A.actor)\n/proc/global_helper(mob/M)\n    return issilicon(M)\n"),
 ("shared_helper","/obj/machinery/proc/zfirst(datum/act/op/A)\n    return helper(A.actor)\n/obj/machinery/proc/asecond(datum/act/op/A)\n    return helper(A.actor)\n/obj/machinery/proc/helper(M)\n    return issilicon(M)\n"),
 ("versions","/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n/obj/machinery/use(datum/act/op/A)\n    return isrobot(A.actor)\n"),
 ("if_else_lines","/obj/machinery/proc/use(datum/act/op/A)\n    if(isAI(A.actor))\n        return 1\n    else if(isrobot(A.actor))\n        return 2\n"),
 ("cyclic_helpers","/obj/machinery/proc/use(datum/act/op/A)\n    return one(A.actor)\n/obj/machinery/proc/one(M)\n    two(M)\n    return issilicon(M)\n/obj/machinery/proc/two(M)\n    return one(M)\n"),
 ("unselected_bad_body","/obj/machinery/proc/plain(M)\n    return )\n/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n"),
];
