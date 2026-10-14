//! Schema-pinned intrinsic presence/type catalog migrated from bootstrap.
//! Only explicitly proven declared types are supported; other metadata is opaque.
use dm_ir::{SymbolId, SymbolTable};
use dm_tree::{IntrinsicMember, MemberKind};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FieldTypeMeaning {
    Known(SymbolId),
    KnownUntyped,
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
pub const CATALOG_SCHEMA: &str = "dm-bootstrap-builtin-fields-v9-native-callee-src-usr";
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
        "/alist",
        "/turf",
        "/particles",
        "/savefile",
        "/callee",
    ] {
        let owner_symbol = symbols.intern(owner)?;
        // Native /image has its own visibility collection; do not infer that
        // field for /atom or /mutable_appearance from their shared field list.
        let extra: &[&str] = if owner == "/image" {
            &["vis_contents", "override"]
        } else {
            &[]
        };
        for name in names(owner).iter().chain(extra) {
            let name_symbol = symbols.intern(name)?;
            let declared_type = match *name {
                "vars" if owner == "/datum" => Some("/list"),
                "screen" if owner == "/client" => Some("/list"),
                "images" if owner == "/client" => Some("/list"),
                "locs" if owner == "/atom/movable" => Some("/list"),
                "particles" if owner == "/atom/movable" => Some("/particles"),
                "vis_contents" if matches!(owner, "/atom/movable" | "/image") => Some("/list"),
                "vis_contents" if owner == "/turf" => Some("/list"),
                "caller" if owner == "/callee" => Some("/callee"),
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
                None if matches!(
                    (owner, *name),
                    ("/world", "sleep_offline" | "visibility")
                        | ("/client", "fps" | "mouse_pointer_icon")
                        | ("/callee", "proc" | "name" | "src" | "usr")
                        | ("/image", "override")
                        | ("/list", "type" | "parent_type" | "len")
                        | ("/alist", "type" | "len")
                ) =>
                {
                    FieldTypeMeaning::KnownUntyped
                }
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
        "/callee" => &["proc", "name", "caller", "src", "usr"],
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
            "fps",
            "mouse_pointer_icon",
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
            // native_world_sleep_offline proves runtime World-field reads and
            // writes. Header policy stays separate; declared type stays opaque.
            "sleep_offline",
            "timezone",
            "visibility",
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
        "/list" => &["type", "parent_type", "len"],
        "/alist" => &["type", "len"],
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
    #[test]
    fn native_probe31_field_receipts_bind_exact_type_knowledge() {
        use sha2::{Digest, Sha256};
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/phase1/native_probe31_fields");
        let receipt: serde_json::Value =
            serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
        assert_eq!(
            receipt["compiler_sha256"],
            "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
        );
        for file in receipt["files"].as_array().unwrap() {
            assert_eq!(
                format!(
                    "{:x}",
                    Sha256::digest(
                        std::fs::read(root.join(file["path"].as_str().unwrap())).unwrap()
                    )
                ),
                file["sha256"].as_str().unwrap()
            );
        }
        let fields = super::fields(&mut super::SymbolTable::default()).unwrap();
        for (owner, name, expected) in [
            (
                "/turf",
                "vis_contents",
                super::FieldTypeMeaning::Known(super::SymbolId::of("/list")),
            ),
            (
                "/callee",
                "caller",
                super::FieldTypeMeaning::Known(super::SymbolId::of("/callee")),
            ),
            ("/callee", "name", super::FieldTypeMeaning::KnownUntyped),
            ("/image", "override", super::FieldTypeMeaning::KnownUntyped),
        ] {
            let field = fields
                .iter()
                .find(|field| {
                    field.owner == super::SymbolId::of(owner)
                        && field.name == super::SymbolId::of(name)
                })
                .unwrap();
            assert_eq!(field.declared_type, expected);
            assert!(field.presence().instance_storage_proven);
        }
    }
    #[test]
    fn native_list_field_receipts_bind_known_untyped_instance_reads() {
        use sha2::{Digest, Sha256};
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/phase1/native_list_fields");
        let receipt: serde_json::Value =
            serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
        assert_eq!(
            receipt["compiler_sha256"],
            "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
        );
        for file in receipt["files"].as_array().unwrap() {
            let bytes = std::fs::read(root.join(file["path"].as_str().unwrap())).unwrap();
            assert_eq!(
                format!("{:x}", Sha256::digest(bytes)),
                file["sha256"].as_str().unwrap()
            );
        }
        let mut symbols = super::SymbolTable::default();
        let fields = super::fields(&mut symbols).unwrap();
        for (family, name, selector) in [
            ("list", "type", 37),
            ("list", "parent_type", 130),
            ("list", "len", 57),
            ("alist", "type", 37),
            ("alist", "len", 57),
        ] {
            let case = format!("{family}_{name}");
            let image = byond_dmb::dmb::Dmb::from_bytes(
                &std::fs::read(root.join(format!("{case}_read/probe.native.bin"))).unwrap(),
            )
            .unwrap();
            assert_eq!(image.string(selector), Some(name.as_bytes()));
            assert_eq!(
                image.proc_code_words(0).unwrap(),
                vec![0x33, 65500, 65497, 0, selector, 0x12, 0]
            );
            let log =
                std::fs::read_to_string(root.join(format!("{case}_infer/compile.log"))).unwrap();
            assert!(log.contains(&format!(
                "probe.dm:2:error: value.{name}: unknown variable type"
            )));
            let field = fields
                .iter()
                .find(|field| {
                    field.owner == super::SymbolId::of(&format!("/{family}"))
                        && field.name == super::SymbolId::of(name)
                })
                .unwrap();
            assert_eq!(field.declared_type, super::FieldTypeMeaning::KnownUntyped);
            assert!(field.presence().instance_storage_proven);
        }
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
        assert!(engine
            .hierarchy()
            .parents
            .iter()
            .any(|row| row.0 == super::SymbolId::of("/alist")));
    }
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
        let sleep = field("/world", "sleep_offline");
        assert_eq!(sleep.declared_type, FieldTypeMeaning::KnownUntyped);
        assert!(sleep.presence().instance_storage_proven);
        for (owner, name, path) in [
            ("/atom/movable", "locs", "/list"),
            ("/client", "images", "/list"),
            ("/atom/movable", "particles", "/particles"),
        ] {
            assert_eq!(
                field(owner, name).declared_type,
                FieldTypeMeaning::Known(SymbolId::of(path))
            );
        }
        assert_eq!(
            field("/world", "timezone").declared_type,
            FieldTypeMeaning::Unsupported
        );
        for (owner, name) in [
            ("/world", "visibility"),
            ("/client", "fps"),
            ("/client", "mouse_pointer_icon"),
        ] {
            assert_eq!(
                field(owner, name).declared_type,
                FieldTypeMeaning::KnownUntyped
            );
            assert!(field(owner, name).presence().instance_storage_proven);
        }
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
