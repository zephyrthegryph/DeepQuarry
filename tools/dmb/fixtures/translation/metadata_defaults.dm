/mob/metadata_defaults
/mob/metadata_defaults/invisible
    see_invisible = 7
/mob/metadata_defaults/invisible/child
    sight = 256
/mob/metadata_defaults/wide_sight
    sight = 256
/mob/metadata_defaults/zero_dark
    see_in_dark = 0
/mob/metadata_defaults/zero_dark/child
    see_invisible = 9
/mob/metadata_defaults/two_dark
    see_in_dark = 2
/mob/metadata_defaults/two_dark/child
    see_invisible = 11

/proc/metadata_force_modern_compatibility()
    return alist("key" = 1)
