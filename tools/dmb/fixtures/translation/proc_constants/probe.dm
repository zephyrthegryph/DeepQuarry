var/const/procedure_reference = /proc/answer
var/const/procedure_alias = procedure_reference
var/gender_male = MALE
var/gender_female = FEMALE
var/gender_plural = PLURAL
var/gender_neuter = NEUTER
/proc/answer()
    return 42
/atom/proc/native_fields()
    return list(x, y, z, suffix)
/atom/movable/proc/native_locs()
    return list(locs, vis_contents, vis_locs, vis_flags, particles)
/client/proc/native_gender()
    return list(gender, dir)


/world/proc/native_params()
    return params

/turf/proc/native_visuals()
    return list(vis_contents, vis_locs, vis_flags)
/proc/native_exception(exception/e)
    return e
/obj/verb/native_src()
    set src in view(usr, 1)
    return

/proc/trailing_argument(obj/instance/)
    return instance
/datum/ctor_value
    var/value = 7
/datum/ctor_base
    var/matrix/transformation
    var/datum/ctor_value/instance
    var/observed
    New()
        observed = instance.value
/datum/ctor_base/child
    transformation = matrix()
    instance = new
/proc/annotated_return(appearance/A, generator/G) as /datum/ctor_value
    return new /datum/ctor_value
/atom/proc/native_render_fields()
    return list(text, render_source, render_target)
/client/proc/native_version()
    return list(byond_version, byond_build)
/world/proc/native_host()
    return host
/datum/annotated_vars
    var/frequency as num
    var/var/obj/interim
    proc/get_fields()
        return list(frequency, interim)
/datum/ctor_base/proc/under_score_method()
    return 17
/particles/native_color_zero
    color = 0
/obj/native_color_null
    color = null

/particles/native_color_zero

    position = generator("circle", 0, 16, NORMAL_RAND)

/datum/material_probe
    var/density
/datum/material_probe/child
    density = 30


/datum/ctor_base/proc/renamed_method()
    set name = "Method title"
    return 17
/obj/native_vis_flags
    vis_flags = VIS_INHERIT_ID | VIS_INHERIT_PLANE
/datum/proc_holder
    var/handler
/datum/proc_holder/child
    handler = /proc/answer
/proc/nested_background()
    if(0)
        set background = 1
    return 2
/image/native_maptext
    maptext_width = 256
    maptext_height = 64
    maptext_x = -4
    maptext_y = -6
/obj/native_generic_defaults
    pixel_z = 3
    pixel_w = 4
    render_source = "foo"
    render_target = "bar"
    screen_loc = "1,1"
    bound_width = 64

/datum/block_string_default
	var/description = {"First line
Second line"}

/datum/escaped_block_string_default
	var/proper_description = "\proper Some Name"
	var/escaped_description = {"First \"quoted\" line
Second line with \[literal bracket\] and \n escape"}

/datum/static_default_source
	var/field = 9
/datum/static_default_source/child
	field = 12
/datum/static_default_consumer
	var/static_reference = /datum/static_default_source/child::field

/obj/native_pointer_defaults
	desc = "\proper Quoted \"description\""
	infra_luminosity = 6
	mouse_drag_pointer = MOUSE_ACTIVE_POINTER
	mouse_over_pointer = MOUSE_HAND_POINTER

/datum/trailing_member_header
/datum/trailing_member_header/proc/receive_signal(datum/signal/signal)
	return 1
/datum/trailing_member_header/child
/datum/trailing_member_header/child/receive_signal/(datum/signal/signal)
	return 3

/datum/inherited_proc_base/proc/inherited_method()
	return 13
/datum/inherited_proc_base/child
/datum/proc_path_consumer
	var/inherited_proc_reference = /datum/inherited_proc_base/proc/inherited_method
var/inherited_global_reference = /datum/inherited_proc_base/proc/inherited_method
var/inherited_proc_name = nameof(/datum/inherited_proc_base/child.proc/inherited_method)
var/global_proc_namespace = /datum/inherited_proc_base/proc
/datum/proc_path_consumer
	var/local_proc_namespace = /datum/inherited_proc_base/proc
	var/verb_reference = /datum/proc_path_consumer/verb/action
	var/verb_instance = new /datum/proc_path_consumer/verb/action()
/datum/proc_path_consumer/verb/action()
	return 13
var/global_verb_reference = /datum/proc_path_consumer/verb/action
