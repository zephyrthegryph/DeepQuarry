//! Schema-pinned intrinsic presence/type catalog migrated from bootstrap.
//! Only explicitly proven declared types are supported; other metadata is opaque.
use dm_ir::{SymbolId, SymbolTable};
use dm_tree::{IntrinsicMember, MemberKind};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FieldTypeMeaning {
    Known(SymbolId),
    Unsupported,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CatalogField {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub declared_type: FieldTypeMeaning,
}
/// Mirrors the pinned native bootstrap inventory. It is not a claim that all
/// BYOND versions expose exactly this catalog or that source defaults are known.
pub const CATALOG_SCHEMA: &str = "dm-bootstrap-builtin-fields-v5-native-list-receivers";
pub fn fields(symbols: &mut SymbolTable) -> Result<Vec<CatalogField>, dm_ir::SymbolCollision> {
    let mut fields = Vec::new();
    for owner in [
        "/datum",
        "/atom",
        "/image",
        "/mutable_appearance",
        "/atom/movable",
        "/mob",
        "/client",
        "/world",
        "/list",
        "/turf",
        "/particles",
        "/savefile",
    ] {
        let owner_symbol = symbols.intern(owner)?;
        // Native /image has its own visibility collection; do not infer that
        // field for /atom or /mutable_appearance from their shared field list.
        let extra: &[&str] = if owner == "/image" {
            &["vis_contents"]
        } else {
            &[]
        };
        for name in names(owner).iter().chain(extra) {
            let name_symbol = symbols.intern(name)?;
            let declared_type = match *name {
                "vars" if owner == "/datum" => Some("/list"),
                "screen" if owner == "/client" => Some("/list"),
                "vis_contents" if matches!(owner, "/atom/movable" | "/image") => Some("/list"),
                "loc" => Some("/atom"),
                "contents" | "overlays" | "underlays" | "filters" | "verbs" => Some("/list"),
                "dir" if owner == "/savefile" => Some("/list"),
                "client" => Some("/client"),
                "mob" => Some("/mob"),
                "transform" => Some("/matrix"),
                _ => None,
            };
            let declared_type = match declared_type {
                Some(path) => FieldTypeMeaning::Known(symbols.intern(path)?),
                None => FieldTypeMeaning::Unsupported,
            };
            fields.push(CatalogField {
                owner: owner_symbol,
                name: name_symbol,
                declared_type,
            });
        }
    }
    Ok(fields)
}
impl CatalogField {
    /// Proven instance-field presence. No wire flags become source modifiers.
    pub fn presence(&self) -> IntrinsicMember {
        IntrinsicMember {
            owner: self.owner,
            name: self.name,
            kind: MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: true,
        }
    }
}
pub fn names(path: &str) -> &'static [&'static str] {
    match path {
        // BYOND reference: /savefile/var, including compile-time compatibility
        // defaults. Header emission is a separate ABI policy, not a field slot.
        // https://www.byond.com/docs/ref/info.html#savefile/var/byond_version
        "/savefile" => &["byond_version", "byond_build", "cd", "dir", "eof", "name"],
        "/datum" => &["type", "parent_type", "vars", "tag"],
        "/atom" | "/image" | "/mutable_appearance" => &[
            "name",
            "desc",
            "gender",
            "loc",
            "x",
            "y",
            "z",
            "suffix",
            "text",
            "render_source",
            "render_target",
            "contents",
            "icon",
            "icon_state",
            "dir",
            "layer",
            "plane",
            "density",
            "opacity",
            "mouse_opacity",
            "invisibility",
            "luminosity",
            "infra_luminosity",
            "mouse_drag_pointer",
            "mouse_over_pointer",
            "pixel_x",
            "pixel_y",
            "pixel_z",
            "pixel_w",
            "color",
            "alpha",
            "transform",
            "blend_mode",
            "appearance",
            "appearance_flags",
            "overlays",
            "underlays",
            "filters",
            "maptext",
            "maptext_width",
            "maptext_height",
            "maptext_x",
            "maptext_y",
            "verbs",
        ],
        "/atom/movable" => &[
            "bound_x",
            "bound_y",
            "bound_width",
            "bound_height",
            "step_size",
            "glide_size",
            "screen_loc",
            "animate_movement",
            "locs",
            "vis_contents",
            "vis_locs",
            "vis_flags",
            "particles",
        ],
        "/mob" => &[
            "client",
            "key",
            "ckey",
            "sight",
            "see_in_dark",
            "see_invisible",
            "group",
        ],
        "/client" => &[
            // Current pinned compile-only source assignment/read/write control:
            // phase0/link/client_intrinsic_presence. Metadata stays opaque.
            "preload_rsc",
            // phase0/link/client_script_current and script_storage certify
            // authored header text plus positive instance reads/writes.
            "script",
            "gender",
            "dir",
            "byond_version",
            "byond_build",
            "address",
            "authentication",
            "ckey",
            "color",
            "computer_id",
            "connection",
            "eye",
            "images",
            "inactivity",
            "key",
            "lazy_eye",
            "mob",
            "perspective",
            "pixel_x",
            "pixel_y",
            "pixel_z",
            "screen",
            "show_map",
            "show_popup_menus",
            "show_verb_panel",
            "statobj",
            "view",
            "virtual_eye",
            "control_freak",
            "verbs",
        ],
        "/world" => &[
            // Native Src getter proofs; defaults/modifiers remain opaque.
            "internet_address",
            "map_cpu",
            "host",
            "params",
            "name",
            "status",
            "hub",
            "hub_password",
            "url",
            "address",
            "port",
            "time",
            "timeofday",
            "realtime",
            "tick_lag",
            "fps",
            "tick_usage",
            "cpu",
            "maxx",
            "maxy",
            "maxz",
            "view",
            "log",
            "contents",
            "system_type",
            "version",
            "byond_version",
            "byond_build",
            "params",
            "map_format",
            // Compile-time header field observed in the pinned
            // declaration_metadata fixture; its default/type remain opaque.
            "cache_lifespan",
            "icon_size",
            "mob",
            "turf",
            "area",
        ],
        "/list" => &["len"],
        "/turf" => &["vis_contents", "vis_locs", "vis_flags"],
        "/particles" => &[
            "width",
            "height",
            "count",
            "spawning",
            "lifespan",
            "fade",
            "fadein",
            "icon",
            "icon_state",
            "color",
            "color_change",
            "position",
            "velocity",
            "gravity",
            "drift",
            "scale",
            "grow",
            "rotation",
            "spin",
            "friction",
            "bound1",
            "bound2",
            "gradient",
            "transform",
        ],
        _ => &[],
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn catalog_exposes_known_types_without_inventing_default_metadata() {
        let mut symbols = SymbolTable::default();
        let fields = fields(&mut symbols).unwrap();
        let field = |owner, name| {
            fields
                .iter()
                .find(|f| f.owner == SymbolId::of(owner) && f.name == SymbolId::of(name))
                .unwrap()
        };
        assert_eq!(
            field("/atom", "loc").declared_type,
            FieldTypeMeaning::Known(SymbolId::of("/atom"))
        );
        assert_eq!(
            field("/atom", "icon").declared_type,
            FieldTypeMeaning::Unsupported
        );
        assert_eq!(
            field("/client", "mob").declared_type,
            FieldTypeMeaning::Known(SymbolId::of("/mob"))
        );
        let preload = field("/client", "preload_rsc");
        assert_eq!(preload.declared_type, FieldTypeMeaning::Unsupported);
        assert!(preload.presence().instance_storage_proven);
        assert!(fields.iter().all(|f| f.presence().shared_owner.is_none()));
    }

    #[test]
    fn native_intrinsic_field_receipts_bind_list_receivers_and_instance_storage() {
        use sha2::{Digest, Sha256};
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/phase1/native_intrinsic_field_types");
        let receipt: serde_json::Value =
            serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
        assert_eq!(
            receipt["compiler_sha256"],
            "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
        );
        for case in receipt["cases"].as_array().unwrap() {
            for (file, expected) in case["files"].as_object().unwrap() {
                let bytes =
                    std::fs::read(root.join(case["name"].as_str().unwrap()).join(file)).unwrap();
                assert_eq!(
                    format!("{:x}", Sha256::digest(&bytes)),
                    expected.as_str().unwrap()
                );
            }
        }
        let mut symbols = SymbolTable::default();
        let catalog = fields(&mut symbols).unwrap();
        for (case, owner, name, selector) in [
            ("datum_vars", "/datum", "vars", 94),
            ("client_screen", "/client", "screen", 168),
            ("movable_vis_contents", "/atom/movable", "vis_contents", 281),
            ("image_vis_contents", "/image", "vis_contents", 281),
        ] {
            let image = byond_dmb::dmb::Dmb::from_bytes(
                &std::fs::read(root.join(case).join("probe.native.bin")).unwrap(),
            )
            .unwrap();
            assert_eq!(image.string(selector), Some(name.as_bytes()));
            assert_eq!(image.string(25), Some(b"Copy".as_slice()));
            assert_eq!(
                image.proc_code_words(0).unwrap(),
                vec![0x29, 65500, 65486, 65500, selector, 65501, 25, 0, 0x12, 0]
            );
            let field = catalog
                .iter()
                .find(|field| {
                    field.owner == SymbolId::of(owner) && field.name == SymbolId::of(name)
                })
                .unwrap();
            assert_eq!(
                field.declared_type,
                FieldTypeMeaning::Known(SymbolId::of("/list"))
            );
            assert!(field.presence().instance_storage_proven);
        }
        for (case, name, selector) in [
            ("world_internet_address", "internet_address", 204),
            ("world_map_cpu", "map_cpu", 315),
        ] {
            let image = byond_dmb::dmb::Dmb::from_bytes(
                &std::fs::read(root.join(case).join("probe.native.bin")).unwrap(),
            )
            .unwrap();
            assert_eq!(image.string(selector), Some(name.as_bytes()));
            assert_eq!(
                image.proc_code_words(0).unwrap(),
                vec![0x33, 65500, 65486, selector, 0x12, 0]
            );
            let field = catalog
                .iter()
                .find(|field| {
                    field.owner == SymbolId::of("/world") && field.name == SymbolId::of(name)
                })
                .unwrap();
            assert_eq!(field.declared_type, FieldTypeMeaning::Unsupported);
            assert!(field.presence().instance_storage_proven);
        }
        for case in ["untyped_copy", "world_map_cpu_write", "datum_vars_new"] {
            let row = receipt["cases"]
                .as_array()
                .unwrap()
                .iter()
                .find(|row| row["name"] == case)
                .unwrap();
            assert_ne!(row["exit_code"].as_i64().unwrap(), 0);
            assert!(row["log"].as_str().unwrap().contains(":2:error:"));
        }
    }
}
