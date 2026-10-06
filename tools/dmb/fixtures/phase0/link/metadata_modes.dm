/obj/phase0_metadata
    verb/world_mode(value as text)
        set name = "A displayed"
        set desc = "metadata all flags"
        set category = null
        set src in world
        set invisibility = 7
        set waitfor = 0
        set hidden = 1
        set background = 1
        set instant = 1
        set popup_menu = 0
        return value
    verb/usr_mode()
        set name = "Z displayed"
        set category = "Visible"
        set src in usr
        set invisibility = 0
        set waitfor = 1
        set hidden = 0
        set background = 0
        set instant = 0
        set popup_menu = 1
        return "usr"
    verb/loc_mode()
        set src in usr.loc
        return "loc"
    verb/view_mode()
        set src in view(1)
        return "view"
/world/New()
    ..()
    var/obj/phase0_metadata/O = new
    var/list/verbs_seen = list()
    for(var/V in O.verbs)
        verbs_seen += "[V]"
    phase0_emit("metadata_verbs", verbs_seen)
    phase0_emit("metadata_source_paths", list("[/obj/phase0_metadata/verb/world_mode]", "[/obj/phase0_metadata/verb/usr_mode]", "[/obj/phase0_metadata/verb/loc_mode]", "[/obj/phase0_metadata/verb/view_mode]"))
    phase0_finish()
