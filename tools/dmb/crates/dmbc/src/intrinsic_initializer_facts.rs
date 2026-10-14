//! Finite native mutation acceptance facts; never synthetic modifier masks.
use dm_ir::SymbolId;
const PAIRS: &[(&str, &str)] = &[
    ("/atom", "alpha"),
    ("/atom", "appearance_flags"),
    ("/atom", "blend_mode"),
    ("/atom", "color"),
    ("/atom", "density"),
    ("/atom", "desc"),
    ("/atom", "dir"),
    ("/atom", "gender"),
    ("/atom", "icon"),
    ("/atom", "icon_state"),
    ("/atom", "infra_luminosity"),
    ("/atom", "invisibility"),
    ("/atom", "layer"),
    ("/atom", "luminosity"),
    ("/atom", "maptext_height"),
    ("/atom", "maptext_width"),
    ("/atom", "maptext_x"),
    ("/atom", "maptext_y"),
    ("/atom", "mouse_drag_pointer"),
    ("/atom", "mouse_opacity"),
    ("/atom", "mouse_over_pointer"),
    ("/atom", "name"),
    ("/atom", "opacity"),
    ("/atom", "pixel_x"),
    ("/atom", "pixel_y"),
    ("/atom", "pixel_z"),
    ("/atom", "plane"),
    ("/atom", "render_target"),
    ("/atom", "suffix"),
    ("/atom", "transform"),
    ("/atom/movable", "animate_movement"),
    ("/atom/movable", "bound_height"),
    ("/atom/movable", "bound_width"),
    ("/atom/movable", "glide_size"),
    ("/atom/movable", "screen_loc"),
    ("/atom/movable", "vis_flags"),
    ("/image", "appearance_flags"),
    ("/image", "maptext_height"),
    ("/image", "maptext_width"),
    ("/image", "maptext_x"),
    ("/image", "maptext_y"),
    ("/image", "mouse_opacity"),
    ("/image", "plane"),
    ("/mob", "see_in_dark"),
    ("/mob", "see_invisible"),
    ("/mob", "sight"),
    ("/turf", "vis_flags"),
];
pub fn certified(owner: SymbolId, name: SymbolId) -> bool {
    static INDEX: std::sync::OnceLock<std::collections::HashSet<(SymbolId, SymbolId)>> =
        std::sync::OnceLock::new();
    INDEX
        .get_or_init(|| {
            PAIRS
                .iter()
                .map(|(path, field)| (SymbolId::of(path), SymbolId::of(field)))
                .collect()
        })
        .contains(&(owner, name))
}
pub fn identity() -> u128 {
    static IDENTITY: std::sync::OnceLock<u128> = std::sync::OnceLock::new();
    *IDENTITY.get_or_init(|| {
        xxhash_rust::xxh3::xxh3_128(include_bytes!(
            "../../../fixtures/phase1/intrinsic_initializer_mutability/receipt.json"
        ))
    })
}
pub fn template_identity() -> u128 {
    static IDENTITY: std::sync::OnceLock<u128> = std::sync::OnceLock::new();
    *IDENTITY.get_or_init(|| {
        xxhash_rust::xxh3::xxh3_128(include_bytes!("../../../fixtures/native_template.bin"))
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_mutability_receipt_has_exact_native_src_assignment() {
        let dmb = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/phase1/intrinsic_initializer_mutability/control.native.bin"
        ))
        .unwrap();
        assert_eq!(PAIRS.len(), 47);
        for &(owner, name) in PAIRS {
            let path = format!("{owner}/proc/dq_mutable_{name}");
            let id = dmb
                .procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let code = dmb.proc_code_words(id).unwrap();
            assert_eq!(&code[..6], &[0x33, 65510, 0x34, 65500, 65486, code[5]]);
            assert_eq!(code[6], 0);
            assert_eq!(code.len(), 7);
            assert_eq!(dmb.string(code[5]), Some(name.as_bytes()));
            assert!(certified(SymbolId::of(owner), SymbolId::of(name)));
        }
        assert!(!certified(SymbolId::of("/datum"), SymbolId::of("name")));
        assert!(!certified(SymbolId::of("/atom"), SymbolId::of("type")));
    }
}
