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
pub const CATALOG_SCHEMA: &str = "dm-bootstrap-builtin-fields-v1";
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
    ] {
        let owner_symbol = symbols.intern(owner)?;
        for name in names(owner) {
            let name_symbol = symbols.intern(name)?;
            let declared_type = match *name {
                "loc" => Some("/atom"),
                "contents" | "overlays" | "underlays" | "filters" | "verbs" => Some("/list"),
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
        }
    }
}
pub fn names(path: &str) -> &'static [&'static str] {
    match path {
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
        assert!(fields.iter().all(|f| f.presence().shared_owner.is_none()));
    }
}
