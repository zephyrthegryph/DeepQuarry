/obj/appearance_base
    name = "base name"
    desc = "base description"
    icon = 'tiny.png'
    icon_state = "base state"
    alpha = 191
    dir = EAST
    color = "#123456"
    density = 1
    opacity = 1
    layer = 6
    plane = 3
    pixel_x = -3
    pixel_y = 5
    mouse_opacity = 0
    gender = PLURAL
    luminosity = 2
    glide_size = 5
    appearance_flags = 64
    blend_mode = 2
    maptext = "base maptext"
    maptext_width = 17
    maptext_height = 19
    maptext_x = 2
    maptext_y = -2
    var/unrelated = 1
/obj/appearance_base/alpha_only
    alpha = 177
/obj/appearance_base/alpha_only/dir_only
    dir = WEST
/obj/appearance_base/alpha_only/dir_only/reopened
    unrelated = 7
/obj/appearance_base/alpha_only/dir_only/reopened
    var/another_unrelated = 9
/obj/appearance_base/name_only
    name = "child name"
/obj/appearance_base/state_only
    icon_state = "child state"
/obj/appearance_base/null_icon
    icon = null
/obj/appearance_other
    name = "other name"
    icon_state = "other state"
/obj/appearance_alias
    parent_type = /obj/appearance_base
    alpha = 163
/obj/implicit_base
    alpha = 191
/obj/implicit_base/child
    alpha = 177
/obj/explicit_text
    name = "explicit text name"
    text = "T"
/obj/explicit_text/child
    alpha = 177
/obj/explicit_text/null_text
    text = null
/obj/appearance_base/null_name
    name = null
/obj/appearance_base/null_desc
    desc = null
/obj/explicit_text/name_override
    name = "child name"
/obj/matrix_appearance
    transform = matrix(1,2,3,4,5,6)
    color = list(1,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,1,0)
/obj/matrix_appearance/child
    alpha = 177
/custom_appearance
    parent_type = /obj
    name = "custom alias name"
    desc = "custom alias description"
    icon = 'tiny.png'
    icon_state = "custom alias state"
    alpha = 157
    density = 1
    dir = EAST
/custom_appearance/child
    var/unrelated = 7

/obj/appearance_base/null_name/child
    alpha = 177
