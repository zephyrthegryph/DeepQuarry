/client/proc/player_panel()
    return
/datum/admin_verb
    var/name
    var/description
    var/category
    var/permissions
    var/verb_path
    var/enabled
/datum/admin_verb/player_panel_new { name="Panel"; description="Open"; category="Admin"; permissions=(((1<<18)-1)); verb_path=/client/proc/player_panel; enabled=1; }