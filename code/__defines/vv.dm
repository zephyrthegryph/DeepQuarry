#define VV_NUM "Number"
#define VV_TEXT "Text"
#define VV_MESSAGE "Multiline Text"
#define VV_COLOR "Color"
#define VV_COLOR_MATRIX "Color Matrix"
#define VV_ICON "Icon"
#define VV_ATOM_REFERENCE "Atom Reference"
#define VV_DATUM_REFERENCE "Datum Reference"
#define VV_MOB_REFERENCE "Mob Reference"
#define VV_CLIENT "Client"
#define VV_ATOM_TYPE "Atom Typepath"
#define VV_DATUM_TYPE "Datum Typepath"
#define VV_TYPE "Custom Typepath"
#define VV_FILE "File"
#define VV_LIST "List"
#define VV_NEW_ATOM "New Atom"
#define VV_NEW_DATUM "New Datum"
#define VV_NEW_TYPE "New Custom Typepath"
#define VV_NEW_LIST "New List"
#define VV_NULL "NULL"
#define VV_INFINITY "Infinity"
#define VV_RESTORE_DEFAULT "Restore to Default"
#define VV_MARKED_DATUM "Marked Datum"
#define VV_TAGGED_DATUM "Tagged Datum"
#define VV_BITFIELD "Bitfield"
#define VV_TEXT_LOCATE "Custom Reference Locate"
#define VV_PROCCALL_RETVAL "Return Value of Proccall"

#define VV_MSG_MARKED "<br>" + span_small(span_red(span_bold("Marked Object")))
#define VV_MSG_TAGGED(num) "<br>" + span_small(span_red(span_bold("Tagged Datum #[num]")))
#define VV_MSG_EDITED "<br>" + span_small(span_red(span_bold("Var Edited")))
#define VV_MSG_DELETED "<br>" + span_small(span_red(span_bold("Deleted")))

#define VV_NORMAL_LIST_NO_EXPAND_THRESHOLD 50
#define VV_SPECIAL_LIST_NO_EXPAND_THRESHOLD 150

//#define IS_VALID_ASSOC_KEY(V) (istext(V) || ispath(V) || isdatum(V) || islist(V))
#define IS_VALID_ASSOC_KEY(V) (!isnum(V)) //hhmmm..

//General helpers
#define VV_HREF_TARGET_INTERNAL(target, href_key) "byond://?_src_=vars;[HrefToken()];[href_key]=TRUE;[VV_HK_TARGET]=[REF(target)]"
#define VV_HREF_TARGETREF_INTERNAL(targetref, href_key) "byond://?_src_=vars;[HrefToken()];[href_key]=TRUE;[VV_HK_TARGET]=[targetref]"
#define VV_HREF_TARGET(target, href_key, text) "<a href='[VV_HREF_TARGET_INTERNAL(target, href_key)]'>[text]</a>"
#define VV_HREF_TARGETREF(targetref, href_key, text) "<a href='[VV_HREF_TARGETREF_INTERNAL(targetref, href_key)]'>[text]</a>"
#define VV_HREF_TARGET_1V(target, href_key, text, varname) "<a href='[VV_HREF_TARGET_INTERNAL(target, href_key)];[VV_HK_VARNAME]=[varname]'>[text]</a>" //for stuff like basic varedits, one variable
#define VV_HREF_TARGETREF_1V(targetref, href_key, text, varname) "<a href='[VV_HREF_TARGETREF_INTERNAL(targetref, href_key)];[VV_HK_VARNAME]=[varname]'>[text]</a>"

//Helper for linking to a VV_TOPIC op (topic_in(VV_TOPIC, href_key)) in general
#define VV_TOPIC_LINK(datum, href_key, text) "<a href='byond://?_src_=vars;[HrefToken()];[href_key]=TRUE;target=[REF(datum)]'>text</a>"

//Helpers for vv_get_dropdown()
#define VV_DROPDOWN_OPTION(href_key, name) . += "<option value='?_src_=vars;[HrefToken()];[href_key]=TRUE;target=[REF(src)]'>[name]</option>"

// View Variables href actions (doc/rewrite/final_api.html section 13). A `_src_=vars` href reaches
// /client/proc/vv_topic(), which checks R_VAREDIT and the admin href token, then
// topic_dispatch_vv(): the `target` datum's ops in VV_TOPIC first, then the admin holder's ops in
// VV_ADMIN_TOPIC. Both namespaces are unreachable from plain Topic() hrefs.
/// Namespace of per-type actions on the VV'd datum (the dropdown actions).
#define VV_TOPIC "vv"
/// Namespace of actions on the admin's own client (basic edits, lists, Vars, rename, ...).
#define VV_ADMIN_TOPIC "vv_admin"
/// A VV dropdown action on datums of PATH; the handler runs on the VV'd datum as proc(mob/user, list/args).
#define VV_TOPIC_ACTION(PATH, KEY, PROC, SPECS...) ##PATH/topic_actions() { return topic_register(..(), KEY, PROC, list(SPECS), VV_TOPIC); }
/// A VV action handled by the admin's client; declare the VV target as a TOPIC_REF spec.
#define VV_ADMIN_TOPIC_ACTION(KEY, PROC, SPECS...) /client/topic_actions() { return topic_register(..(), KEY, PROC, list(SPECS), VV_ADMIN_TOPIC); }

// VV HREF KEYS
#define VV_HK_TARGET "target"
#define VV_HK_VARNAME "targetvar" //name or index of var for 1 variable targeting hrefs.

// VV list action keys (view_variables/topic_list.dm)
#define VV_HK_LIST_ADD "listadd"
#define VV_HK_LIST_EDIT "listedit"
#define VV_HK_LIST_CHANGE "listchange"
#define VV_HK_LIST_REMOVE "listremove"
#define VV_HK_LIST_ERASE_NULLS "listnulls"
#define VV_HK_LIST_ERASE_DUPES "listdupes"
#define VV_HK_LIST_SHUFFLE "listshuffle"
#define VV_HK_LIST_SET_LENGTH "listlen"

// VV basic action keys (view_variables/topic_basic.dm)
#define VV_HK_BASIC_EDIT "datumedit"
#define VV_HK_BASIC_CHANGE "datumchange"
#define VV_HK_BASIC_MASSEDIT "massedit"

// /datum
#define VV_HK_DELETE "delete"
#define VV_HK_EXPOSE "expose"
#define VV_HK_CALLPROC "proc_call"
#define VV_HK_MARK "mark"
#define VV_HK_TAG "tag"
#define VV_HK_ADDCOMPONENT "addcomponent"
#define VV_HK_REMOVECOMPONENT "removecomponent"
#define VV_HK_MASS_REMOVECOMPONENT "massremovecomponent"
#define VV_HK_MODIFY_TRAITS "modtraits"

// /atom
#define VV_HK_MODIFY_TRANSFORM "atom_transform"
#define VV_HK_SPIN_ANIMATION "atom_spin"
#define VV_HK_STOP_ALL_ANIMATIONS "stop_animations"
#define VV_HK_MODIFY_GREYSCALE "modify_greyscale"
#define VV_HK_ADD_REAGENT "addreagent"
#define VV_HK_SHOW_HIDDENPRINTS "show_hiddenprints"
#define VV_HK_TRIGGER_EMP "empulse"
#define VV_HK_TRIGGER_EXPLOSION "explode"
#define VV_HK_AUTO_RENAME "auto_rename"
#define VV_HK_EDIT_FILTERS "edit_filters"
#define VV_HK_EDIT_PARTICLES "edit_particles"
#define VV_HK_EDIT_COLOR_MATRIX "edit_color_matrix"
#define VV_HK_TEST_MATRIXES "test_matrixes"
#define VV_HK_ADD_AI "add_ai"
#define VV_HK_ARMOR_MOD "mod_obj_armor"
#define VV_HK_ATOM_EXPLODE "turf_explode"
#define VV_HK_ATOM_EMP "turf_emp"

// /atom/movable
#define VV_HK_OBSERVE_FOLLOW "observe_follow"
#define VV_HK_GET_MOVABLE "get_movable"
#define VV_HK_DEADCHAT_PLAYS "deadchat_plays"

// /obj
#define VV_HK_OSAY "osay"
#define VV_HK_FAKE_CONVO "fakepdapropconvo"
#define VV_HK_MASS_DEL_TYPE "mass_delete_type"

// /mob
#define VV_HK_GIB "gib"
#define VV_HK_GIVE_MOB_ACTION "give_mob_action"
#define VV_HK_REMOVE_MOB_ACTION "remove_mob_action"
#define VV_HK_GIVE_SPELL "give_spell"
#define VV_HK_REMOVE_SPELL "remove_spell"
#define VV_HK_GIVE_MODIFIER "give_modifier"
#define VV_HK_GIVE_DISEASE "give_disease"
#define VV_HK_GODMODE "toggle_godmode"
#define VV_HK_DROP_ALL "dropall"
#define VV_HK_REGEN_ICONS "regen_icons"
#define VV_HK_REGEN_ICONS_FULL "regen_icons_full"
#define VV_HK_PLAYER_PANEL "player_panel"
#define VV_HK_BUILDMODE "buildmode"
#define VV_HK_DIRECT_CONTROL "direct_control"
#define VV_HK_GIVE_DIRECT_CONTROL "give_direct_control"
#define VV_HK_OFFER_GHOSTS "offer_ghosts"
#define VV_HK_VIEW_PLANES "view_planes"
#define VV_HK_GIVE_AI "give_ai"
#define VV_HK_GIVE_AI_SPEECH "give_ai_speech"
#define VV_HK_ADDLANGUAGE "addlanguage"
#define VV_HK_REMOVELANGUAGE "remlanguage"
#define VV_HK_ADDVERB "addverb"
#define VV_HK_REMOVEVERB "remverb"
#define VV_HK_ADDORGAN "addorgan"
#define VV_HK_REMOVEORGAN "remorgan"

// /mob/living
#define VV_HK_GIVE_SPEECH_IMPEDIMENT "impede_speech"
#define VV_HK_ADMIN_RENAME "admin_rename"
#define VV_HK_ADD_MOOD "addmood"
#define VV_HK_REMOVE_MOOD "removemood"
#define VV_HK_GIVE_HALLUCINATION "give_hallucination"
#define VV_HK_GIVE_DELUSION_HALLUCINATION "give_hallucination_delusion"
#define VV_HK_GIVE_GUARDIAN_SPIRIT "give_guardian_spirit"

// /mob/living/carbon
#define VV_HK_MODIFY_BODYPART "mod_bodypart"
#define VV_HK_MODIFY_ORGANS "organs_modify"
#define VV_HK_MARTIAL_ART "give_martial_art"
#define VV_HK_GIVE_TRAUMA "give_trauma"
#define VV_HK_CURE_TRAUMA "cure_trauma"

// /mob/living/carbon/human
#define VV_HK_COPY_OUTFIT "copy_outfit"
#define VV_HK_MOD_MUTATIONS "quirkmut"
#define VV_HK_MOD_QUIRKS "quirkmod"
#define VV_HK_SET_SPECIES "setspecies"
#define VV_HK_PURRBATION "purrbation"
#define VV_HK_APPLY_DNA_INFUSION "apply_dna_infusion"
#define VV_HK_TURN_INTO_MMI "turn_into_mmi"
#define VV_HK_TURN_MONKEY "turn_monkey"
#define VV_HK_TURN_ALIEN "turn_alien"
#define VK_HK_TURN_SKELETON "turn_skeleton"
#define VK_HK_TURN_AI "turn_ai"
#define VK_HK_TURN_ROBOT "turn_robot"


// Flags for debug_variable() that do little things to what we end up rendering

/// ALWAYS render a reduced list, useful for fuckoff big datums that need to be condensed for the sake of client load
#define VV_ALWAYS_CONTRACT_LIST (1<<0)
