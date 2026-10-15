//! Application of typed world directives. Interpretation lives in world_projection;
//! this writer only resolves explicit native table identities and writes fields.
use crate::{
    composition::StringIndex,
    world_projection::{DefaultKind, Directive, TextField},
};
use byond_dmb::{dmb::Dmb, ids::NONE};
use dm_ir::SymbolId;

pub trait DefaultBindings {
    /// Mob defaults are mob-table IDs; turf/area defaults are class-table IDs.
    fn index(&self, kind: DefaultKind, path: SymbolId) -> Result<u32, String>;
}
pub(crate) fn apply(
    dmb: &mut Dmb,
    directives: &[Directive],
    pool: &mut StringIndex,
    defaults: &dyn DefaultBindings,
) -> Result<(), String> {
    for directive in directives {
        match directive {
            Directive::Text { field, bytes } => {
                let id = match bytes {
                    Some(bytes) => pool
                        .intern(dmb, bytes)
                        .map_err(|e| format!("world text {e:?}"))?,
                    None => NONE,
                };
                match field {
                    TextField::Name => dmb.world.ids[6] = id,
                    TextField::Status => dmb.world.server_name = id,
                    TextField::Hub => dmb.world.hub_channel_skin[0] = id,
                    TextField::HubPassword => dmb.world.hub_password = id,
                }
            }
            Directive::DefaultType { kind, path } => {
                let id = match path {
                    Some(path) => defaults.index(*kind, *path)?,
                    None => NONE,
                };
                let slot = match kind {
                    DefaultKind::Mob => 0,
                    DefaultKind::Turf => 1,
                    DefaultKind::Area => 2,
                };
                if id != NONE {
                    let valid = if *kind == DefaultKind::Mob {
                        dmb.mobs.get(id as usize).is_some()
                    } else {
                        dmb.classes.get(id as usize).is_some()
                    };
                    if !valid {
                        return Err("world default target is outside its native table".into());
                    }
                }
                dmb.world.ids[slot] = id;
            }
            Directive::Dimension { axis, value } => {
                let dimension = dmb.dimensions.get_mut(*axis).ok_or("invalid world axis")?;
                *dimension = *value;
            }
            Directive::View(value) => {
                dmb.world.view_dimensions = *value;
                dmb.header.flags &= !0x200;
            }
            Directive::TickMilliseconds(value) => dmb.world.tick_lag = *value,
            Directive::Version(value) => dmb.world.version = *value,
            Directive::CacheLifespan(value) => dmb.world.cache_lifespan = *value,
            Directive::IconSize(value) => {
                dmb.world.icon_dimensions_format[0] = *value;
                dmb.world.icon_dimensions_format[1] = *value;
                if dmb.world.savefile_byond_version == 0 {
                    crate::header_compat::raise(dmb, 514, 507);
                }
            }
            Directive::MapFormat(value) => {
                dmb.world.icon_dimensions_format[2] = *value;
                if dmb.world.savefile_byond_version == 0 {
                    crate::header_compat::raise(dmb, 514, 507);
                }
            }
            Directive::Flag { mask, enabled } => {
                if *enabled {
                    dmb.header.flags |= *mask;
                } else {
                    dmb.header.flags &= !*mask;
                }
            }
        }
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    struct NoDefaults;
    impl DefaultBindings for NoDefaults {
        fn index(&self, _: DefaultKind, _: SymbolId) -> Result<u32, String> {
            Err("default was not bound".into())
        }
    }
    #[test]
    fn ordered_name_and_header_updates_keep_last_write_and_exact_bytes() {
        let bytes = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let mut dmb = Dmb::from_bytes(bytes).unwrap();
        let mut pool = StringIndex::build(&dmb).unwrap();
        let directives = vec![
            Directive::Text {
                field: TextField::Name,
                bytes: Some(std::sync::Arc::from(b"first".as_slice())),
            },
            Directive::Text {
                field: TextField::Name,
                bytes: Some(std::sync::Arc::from(b"last".as_slice())),
            },
            Directive::Flag {
                mask: 0x20,
                enabled: true,
            },
            Directive::TickMilliseconds(50),
        ];
        apply(&mut dmb, &directives, &mut pool, &NoDefaults).unwrap();
        assert_eq!(dmb.string(dmb.world.ids[6]), Some(b"last".as_slice()));
        assert_eq!(dmb.world.tick_lag, 50);
        assert_ne!(dmb.header.flags & 0x20, 0);
    }
}
