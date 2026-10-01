//! Native predefined values verified against BYOND 516.1687.
//! Numeric values are IEEE single precision bits; lexical declarations may shadow them.
pub const NUMBERS: &[(&str, u32)] = &[
    ("ANIMATION_CONTINUE", 1140850688),
    ("ANIMATION_END_LOOP", 1098907648),
    ("ANIMATION_END_NOW", 1065353216),
    ("ANIMATION_LINEAR_TRANSFORM", 1073741824),
    ("ANIMATION_PARALLEL", 1082130432),
    ("ANIMATION_RELATIVE", 1132462080),
    ("ANIMATION_SLICE", 1090519040),
    ("AREA_LAYER", 1065353216),
    ("BACK_EASING", 1086324736),
    ("BACKGROUND_LAYER", 1184645120),
    ("BLEND_ADD", 1073741824),
    ("BLEND_DEFAULT", 0),
    ("BLEND_INSET_OVERLAY", 1084227584),
    ("BLEND_MULTIPLY", 1082130432),
    ("BLEND_OVERLAY", 1065353216),
    ("BLEND_SUBTRACT", 1077936128),
    ("BOUNCE_EASING", 1082130432),
    ("CIRCULAR_EASING", 1073741824),
    ("COLORSPACE_HCY", 1077936128),
    ("COLORSPACE_HSL", 1073741824),
    ("COLORSPACE_HSV", 1065353216),
    ("COLORSPACE_RGB", 0),
    ("CONTROL_FREAK_ALL", 1065353216),
    ("CONTROL_FREAK_MACROS", 1082130432),
    ("CONTROL_FREAK_SKIN", 1073741824),
    ("CUBIC_EASING", 1077936128),
    ("DM_BUILD", 1154670592),
    ("DM_VERSION", 1140916224),
    ("EASE_IN", 1115684864),
    ("EASE_OUT", 1124073472),
    ("EDGE_PERSPECTIVE", 1073741824),
    ("EFFECTS_LAYER", 1167867904),
    ("ELASTIC_EASING", 1084227584),
    ("EYE_PERSPECTIVE", 1065353216),
    ("FILTER_COLOR_RGB", 0),
    ("FILTER_COLOR_HSV", 1065353216),
    ("FILTER_COLOR_HSL", 1073741824),
    ("FILTER_COLOR_HCY", 1077936128),
    ("FILTER_OVERLAY", 1065353216),
    ("FILTER_UNDERLAY", 1073741824),
    ("FLOAT_LAYER", 3212836864),
    ("FLOAT_PLANE", 3338665472),
    ("FLY_LAYER", 1084227584),
    ("FORWARD_STEPS", 1065353216),
    ("ICON_ADD", 0),
    ("ICON_AND", 1082130432),
    ("ICON_MULTIPLY", 1073741824),
    ("ICON_OR", 1084227584),
    ("ICON_OVERLAY", 1077936128),
    ("ICON_SUBTRACT", 1065353216),
    ("ICON_UNDERLAY", 1086324736),
    ("ISOMETRIC_MAP", 1065353216),
    ("JSON_ALLOW_COMMENTS", 1073741824),
    ("JSON_PRETTY_PRINT", 1065353216),
    ("JSON_STRICT", 1065353216),
    ("JUMP_EASING", 1090519040),
    ("KEEP_APART", 1115684864),
    ("KEEP_TOGETHER", 1107296256),
    ("LEGACY_MOVEMENT_MODE", 0),
    ("LINEAR_EASING", 0),
    ("LINEAR_RAND", 1073741824),
    ("LONG_GLIDE", 1065353216),
    ("MASK_INVERSE", 1065353216),
    ("MASK_SWAP", 1073741824),
    ("MATRIX_ROTATE", 1084227584),
    ("MATRIX_SCALE", 1086324736),
    ("MATRIX_TRANSLATE", 1088421888),
    ("MOB_LAYER", 1082130432),
    ("MOB_PERSPECTIVE", 0),
    ("MOUSE_ACTIVE_POINTER", 1065353216),
    ("MOUSE_ARROW_POINTER", 1084227584),
    ("MOUSE_CROSSHAIRS_POINTER", 1086324736),
    ("MOUSE_DRAG_POINTER", 1077936128),
    ("MOUSE_DROP_POINTER", 1082130432),
    ("MOUSE_HAND_POINTER", 1088421888),
    ("MOUSE_INACTIVE_POINTER", 0),
    ("NO_CLIENT_COLOR", 1098907648),
    ("NO_STEPS", 0),
    ("NORMAL_RAND", 1065353216),
    ("OBJ_LAYER", 1077936128),
    ("OUTLINE_SHARP", 1065353216),
    ("OUTLINE_SQUARE", 1073741824),
    ("PASS_MOUSE", 1149239296),
    ("PIXEL_MOVEMENT_MODE", 1073741824),
    ("PIXEL_SCALE", 1140850688),
    ("PLANE_MASTER", 1124073472),
    ("PROFILE_AVERAGE", 1082130432),
    ("PROFILE_CLEAR", 1073741824),
    ("PROFILE_REFRESH", 0),
    ("PROFILE_RESTART", 1073741824),
    ("PROFILE_START", 0),
    ("PROFILE_STOP", 1065353216),
    ("QUAD_EASING", 1088421888),
    ("RESET_COLOR", 1073741824),
    ("RESET_ALPHA", 1082130432),
    ("RESET_TRANSFORM", 1090519040),
    ("TILE_BOUND", 1132462080),
    ("TILE_MOVER", 1157627904),
    ("TOPDOWN_MAP", 0),
    ("TURF_LAYER", 1073741824),
    ("NORTH", 1065353216),
    ("SOUTH", 1073741824),
    ("EAST", 1082130432),
    ("WEST", 1090519040),
    ("NORTHEAST", 1084227584),
    ("NORTHWEST", 1091567616),
    ("SOUTHEAST", 1086324736),
    ("SOUTHWEST", 1092616192),
    ("UP", 1098907648),
    ("DOWN", 1107296256),
    ("TRUE", 1065353216),
    ("FALSE", 0),
    ("SEE_BLACKNESS", 1149239296),
    ("SEE_INFRA", 1115684864),
    ("SEE_MOBS", 1082130432),
    ("SEE_OBJS", 1090519040),
    ("SEE_PIXELS", 1132462080),
    ("SEE_SELF", 1107296256),
    ("SEE_THRU", 1140850688),
    ("SEE_TURFS", 1098907648),
    ("SIDE_MAP", 1073741824),
    ("SINE_EASING", 1065353216),
    ("SLIDE_STEPS", 1073741824),
    ("SOUND_MUTE", 1065353216),
    ("SOUND_PAUSED", 1073741824),
    ("SOUND_STREAM", 1082130432),
    ("SOUND_UPDATE", 1098907648),
    ("SQUARE_RAND", 1077936128),
    ("SYNC_STEPS", 1077936128),
    ("TILE_MOVEMENT_MODE", 1065353216),
    ("TILED_ICON_MAP", 1191182336),
    ("TOPDOWN_LAYER", 1176256512),
    ("UNIFORM_RAND", 0),
    ("VIS_HIDE", 1124073472),
    ("VIS_INHERIT_DIR", 1082130432),
    ("VIS_INHERIT_ICON", 1065353216),
    ("VIS_INHERIT_ICON_STATE", 1073741824),
    ("VIS_INHERIT_ID", 1107296256),
    ("VIS_INHERIT_LAYER", 1090519040),
    ("VIS_INHERIT_PLANE", 1098907648),
    ("VIS_UNDERLAY", 1115684864),
    ("WAVE_BOUNDED", 1073741824),
    ("WAVE_SIDEWAYS", 1065353216),
];
pub const STRINGS: &[(&str, &str)] = &[
    ("MS_WINDOWS", "MS Windows"),
    ("UNIX", "UNIX"),
    ("MALE", "male"),
    ("FEMALE", "female"),
    ("PLURAL", "plural"),
    ("NEUTER", "neuter"),
];

#[cfg(test)]
mod tests {
    use super::*;
    use byond_dmb::dmb::Dmb;

    #[test]
    fn gender_strings_match_native_compiler() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/gender_constants.native.bin"
        ))
        .unwrap();
        for variable in &native.variables {
            let Some(name) = native
                .string(variable.name)
                .and_then(|value| std::str::from_utf8(value).ok())
                .and_then(|value| value.strip_prefix("probe_"))
            else {
                continue;
            };
            assert_eq!(variable.kind, 6);
            let value = std::str::from_utf8(native.string(variable.value).unwrap()).unwrap();
            assert_eq!(
                STRINGS
                    .iter()
                    .find(|(candidate, _)| *candidate == name)
                    .map(|(_, value)| *value),
                Some(value)
            );
        }
    }

    #[test]
    fn filter_colors_match_native_compiler() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/filter_constants.native.bin"
        ))
        .unwrap();
        for variable in &native.variables {
            let Some(name) = native
                .string(variable.name)
                .and_then(|value| std::str::from_utf8(value).ok())
                .and_then(|value| value.strip_prefix("probe_"))
            else {
                continue;
            };
            assert_eq!(variable.kind, 42);
            assert_eq!(
                NUMBERS
                    .iter()
                    .find(|(candidate, _)| *candidate == name)
                    .map(|(_, value)| *value),
                Some(variable.value)
            );
        }
    }
}
