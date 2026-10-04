#define SOMETHING 1
// a comment line at the top level
/datum/base
	latent_safe = TRUE
	var/datum/leaked_ref
	var/obj/item/held = null
	var/list/datum/ref_list
	var/tmp/datum/tmp_ref
	var/static/datum/static_ref
	var/global/datum/global_ref
	var/const/datum/const_ref
	var/final/datum/final_ref
	var/tmp/static/datum/both_mods
	var/datum/reg_thing/registry_ref
	var/datum/reg_thing/sub/registry_sub
	var/datum/spaced_reg/spaced_ref
	var/datum/indented_reg/indented_ref
	var/datum/commented_reg/commented_ref
	var/decl/some_decl/def_ref
	var/datum/codec_ref
	var/datum/own_ref
	var/datum/shared_ref
	var/datum/annot_ref
	var/datum/anc_ref
	var/datum/accessor_ref
	var/datum/proto_ref
	var/datum/rel_string_ref
	var/datum/shared_set_ref
	var/datum/default_child
	var/datum/dup_ref
	var/datum/dup_ref
	var/datum/arr[5]
	var/datum/after_comment = null // var/datum/not_here
	var/datum/after_string = "a // b"
	var/icon/res = 'icons/a.dmi'
	var/datum/after_resource
	var/datum/asx as anything
	var/num_value = 1
	var/text_value = "x"
	var/list/plain_list
	var/list/numbers = list(1, 2)
	var/client/cl
	var/sound/snd
	var/matrix/mx
	var/datum/mixed/tmp/odd_type
	var/list/datum/multi = list(
		"a",
		"b")
	var/datum/after_multi
		var/datum/too_deep
	var
		datum/block_ref
		list/mob/block_list = list()
		num_block = 2
	var/tmp
		datum/block_tmp
		list/obj/block_list_tmp
	var/static
		datum/block_static[3]
	var/const
		datum/block_const = null
	var/datum/after_block
	var/unterminated = "oops
	var/datum/after_unterminated
	var/text = {"multi
line var/datum/in_string
text"}
	var/datum/after_raw_string

/datum/base/var/datum/abs_ref
/datum/base/var/tmp/datum/abs_tmp
/datum/base/var/static/list/datum/abs_static
/datum/base/var/list/obj/abs_list

/datum/base/proc/do_thing()
	var/datum/local_in_proc
	return

/datum/base/Initialize(mapload)
	var/datum/init_local
	. = ..()

/datum/base/verb/say_it(mob/user)
	var/datum/verb_local

/datum/base/proc/state_codecs()
	return list("codec_ref" = /datum/state_codec/owned, "other" = /datum/state_codec/other)

/datum/base/ownership()
	. += owns(nameof(own_ref))
	. += shares(nameof(shared_ref))
	. += owns(nameof(annot_ref), policy = OWN_NONE)
	. += rel_one(nameof(abs_ref))

/datum/ownership()
	. += owns(nameof(anc_ref))

/datum/base/proc/writes()
	own_set(src, nameof(accessor_ref), new /datum())
	proto_set(src, nameof(proto_ref), null)
	rel_set(src, "rel_string_ref", null)
	shared_set(src, nameof(shared_set_ref), null)

CAPABILITIES(/datum/base, owns_one(nameof(default_child), starts = /datum/thing))

/proc/global_proc()
	var/datum/global_local

var/datum/global_var_ref
var/list/datum/global_list_ref

/datum/base/lonely_header

/datum/base/with_equals = 5

/datum/spaces
    latent_safe = TRUE
    var/datum/space_ref
    var/tmp/datum/space_tmp
    var
        datum/space_block_ref
    var/list/datum/space_list = list(
        1,
        2)
    var/datum/space_after
	var/datum/mixed_indent_after
