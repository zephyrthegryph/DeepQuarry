// Independent suite-1.11 invalid_set_value observations, not a parity baseline.
/proc/invalid_settings()
    set background = 2
    set waitfor = 1.0
    set hidden = (1)
    set instant = null
    set popup_menu = "yes"
    set name = 1
    set category = /datum
    set desc = null
    set invisibility = 101

/proc/allowed_settings(a)
    set background = 0
    set waitfor = 1
    set hidden = 01
    set instant = 0x1
    set popup_menu = TRUE
    set name = "[a]"
    set category = null
    set desc = "text"
    set invisibility = 0144

/proc/term_shapes(a)
    set name = ("title")
    set category = a
    set desc = a + 1
    set invisibility = 100.0

/proc/prefix_only(a)
    set background = 2
    a = 1
    set waitfor = 2
    if(a)
        set hidden = 2
