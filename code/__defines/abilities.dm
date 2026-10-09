// Abilities. An ability is an op with a menu(button =, bind =) binding that a capability brings to its holder; a source gives it with
// grant(M, capability(), source) and takes it back with revoke(). The op key of a capability's op is "<capability>.<op>": the keys below
// are the ones the keybinding rows (keybindings/keybinding_defaults.dm), the HUD and the tests name.

/// The keybinding id of an ability's dedicated key (keybinding_defaults.dm).
#define ABILITY_KEYBIND(id) "ability_[id]"

// ---- Shadekin powers (shadekin/state/powers/) ----
#define ABILITY_ID_SHADEKIN_PHASE_SHIFT "shadekin_phase.shift"
#define ABILITY_ID_SHADEKIN_REGENERATE_OTHER "shadekin_utility.regenerate_other"
#define ABILITY_ID_SHADEKIN_CREATE_SHADE "shadekin_utility.create_shade"
#define ABILITY_ID_SHADEKIN_DARK_RESPITE "shadekin_dark.dark_respite"
#define ABILITY_ID_SHADEKIN_DARK_MAW "shadekin_dark.dark_maw"
#define ABILITY_ID_SHADEKIN_DARK_TUNNELING "shadekin_dark.dark_tunneling"
#define ABILITY_ID_SHADEKIN_CLEAR_DARK_MAWS "shadekin_dark.clear_dark_maws"

// ---- Dark tunneling's numbers (powers/dark_tunnel/dark_tunneling.dm) ----
#define DARK_TUNNEL_CHANNEL_TIME (60 SECONDS)
#define DARK_TUNNEL_COST 100

// ---- Robot abilities (silicon/robot/robot_abilities.dm) ----
#define ABILITY_ID_ROBOT_TOGGLE_LIGHTS "robot_utility.toggle_lights"
#define ABILITY_ID_ROBOT_PICK_NAME "robot_naming.pick_name"
#define ABILITY_ID_ROBOT_CUSTOMIZE_APPEARANCE "robot_utility.customize_appearance"
#define ABILITY_ID_ROBOT_TOGGLE_GLOWY_STOMACH "robot_utility.toggle_glowy_stomach"
#define ABILITY_ID_ROBOT_SPARK_PLUG "robot_utility.spark_plug"
#define ABILITY_ID_ROBOT_TOGGLE_GRABBABILITY "robot_utility.toggle_grabbability"
#define ABILITY_ID_ROBOT_PURGE_NUTRITION "robot_utility.purge_nutrition"
#define ABILITY_ID_ROBOT_TOGGLE_DECALS "robot_utility.toggle_decals"
#define ABILITY_ID_ROBOT_NOM "robot_utility.nom"
#define ABILITY_ID_ROBOT_SENSOR_MODE "robot_live.sensor_mode"
#define ABILITY_ID_ROBOT_MOUNT "robot_live.mount"
#define ABILITY_ID_ROBOT_TOGGLE_MODULE_1 "robot_live.toggle_module_1"
#define ABILITY_ID_ROBOT_TOGGLE_MODULE_2 "robot_live.toggle_module_2"
#define ABILITY_ID_ROBOT_TOGGLE_MODULE_3 "robot_live.toggle_module_3"
#define ABILITY_ID_ROBOT_RECOLOUR "robot_recolour.recolour"
#define ABILITY_ID_ROBOT_TOGGLE_VTEC "robot_vtec.toggle_vtec"
#define ABILITY_ID_ROBOT_PICK_SHELL "drone_shell.pick_shell"
#define ABILITY_ID_ROBOT_SET_MAIL_TAG "drone_mail.set_mail_tag"
#define ABILITY_ID_ROBOT_EJECT_CARGO "platform_cargo.eject_cargo"
