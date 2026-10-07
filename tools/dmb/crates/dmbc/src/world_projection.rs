//! Typed world-header policy extracted from the retained compiler. It consumes
//! captured values only; table allocation and map defaults remain writer inputs.
use dm_ir::{SemanticValue, SymbolId};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DefaultKind { Mob, Turf, Area }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TextField { Name, Status, Hub, HubPassword }
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Directive {
    Text { field: TextField, bytes: Option<Arc<[u8]>> },
    DefaultType { kind: DefaultKind, path: Option<SymbolId> },
    Dimension { axis: usize, value: u16 },
    View(u16),
    TickMilliseconds(u32),
    Version(u32),
    CacheLifespan(u16),
    IconSize(u16),
    MapFormat(u16),
    Flag { mask: u32, enabled: bool },
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error { Unsupported(String), Invalid(String) }
fn invalid(name: &str) -> Error { Error::Invalid(format!("invalid world.{name}")) }
fn number(name: &str, value: &SemanticValue) -> Result<f32, Error> {
    match value {
        SemanticValue::NumberBits(bits) if f32::from_bits(*bits).is_finite() => Ok(f32::from_bits(*bits)),
        _ => Err(invalid(name)),
    }
}
fn integer(name: &str, value: &SemanticValue, min: f64, max: f64) -> Result<i64, Error> {
    let value = f64::from(number(name, value)?);
    if value.fract() != 0.0 || value < min || value > max { return Err(invalid(name)); }
    Ok(value as i64)
}
fn optional_text(name: &str, value: &SemanticValue) -> Result<Option<Arc<[u8]>>, Error> {
    match value {
        SemanticValue::Null => Ok(None),
        SemanticValue::Text(bytes) => Ok(Some(bytes.clone())),
        _ => Err(invalid(name)),
    }
}
fn view(value: &SemanticValue) -> Result<u16, Error> {
    match value {
        SemanticValue::NumberBits(_) => {
            let radius = number("view", value)?;
            if !(-1.0..=35.0).contains(&radius) { return Err(invalid("view")); }
            let side = (radius as i32 * 2 + 1) as u16;
            Ok((side << 8) | side)
        }
        SemanticValue::Text(bytes) => {
            let text = std::str::from_utf8(bytes).map_err(|_| invalid("view"))?;
            let (width, height) = text.split_once('x').ok_or_else(|| invalid("view"))?;
            let width = width.parse::<u16>().map_err(|_| invalid("view"))?;
            let height = height.parse::<u16>().map_err(|_| invalid("view"))?;
            if width > 255 || height > 255 || u32::from(width) * u32::from(height) > 5041 {
                return Err(invalid("view"));
            }
            Ok(if width == 0 { height / 2 } else { (width << 8) | height })
        }
        _ => Err(invalid("view")),
    }
}
/// Retain every directive in source emission order. Later writes therefore
/// override earlier writes without canonical sorting changing game behavior.
pub fn project<'a>(values: impl IntoIterator<Item = (&'a str, &'a SemanticValue)>) -> Result<Vec<Directive>, Error> {
    let mut result = Vec::new();
    for (name, value) in values {
        let directive = match name {
            "name" | "status" | "hub" | "hub_password" => {
                let field = match name { "name" => TextField::Name, "status" => TextField::Status,
                    "hub" => TextField::Hub, _ => TextField::HubPassword };
                let mut bytes = optional_text(name, value)?;
                if field == TextField::Name && bytes.is_none() { return Err(invalid(name)); }
                if field == TextField::HubPassword {
                    bytes = bytes.map(|bytes| Arc::from(byond_dmb::hash::hub_password_hash(&bytes).into_bytes()));
                }
                Directive::Text { field, bytes }
            }
            "mob" | "turf" | "area" => {
                let path = match value { SemanticValue::Null => None, SemanticValue::Type(path) => Some(*path),
                    _ => return Err(invalid(name)) };
                Directive::DefaultType { kind: match name { "mob" => DefaultKind::Mob,
                    "turf" => DefaultKind::Turf, _ => DefaultKind::Area }, path }
            }
            "maxx" | "maxy" | "maxz" => Directive::Dimension {
                axis: match name { "maxx" => 0, "maxy" => 1, _ => 2 },
                value: integer(name, value, 0.0, 65535.0)? as u16,
            },
            "view" => Directive::View(view(value)?),
            "fps" => Directive::TickMilliseconds(1000 / integer(name, value, 1.0, 100.0)? as u32),
            "tick_lag" => {
                let value = number(name, value)?;
                if value < 0.0 || f64::from(value) * 100.0 > f64::from(u32::MAX) { return Err(invalid(name)); }
                Directive::TickMilliseconds((value * 100.0).round() as u32)
            }
            "version" => Directive::Version(integer(name, value, f64::from(i32::MIN), f64::from(i32::MAX))? as i32 as u32),
            "cache_lifespan" => Directive::CacheLifespan(integer(name, value, 0.0, 65535.0)? as u16),
            "icon_size" => Directive::IconSize(integer(name, value, 0.0, 65535.0)? as u16),
            "map_format" => Directive::MapFormat(integer(name, value, 0.0, 65535.0)? as u16),
            "sleep_offline" | "loop_checks" | "visibility" => {
                let enabled = integer(name, value, f64::from(i32::MIN), f64::from(i32::MAX))? != 0;
                Directive::Flag { mask: match name { "sleep_offline" => 0x20, "loop_checks" => 2, _ => 0x2000 },
                    enabled: if name == "sleep_offline" { enabled } else { !enabled } }
            }
            _ => return Err(Error::Unsupported(format!("world.{name}"))),
        };
        result.push(directive);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn n(value: f32) -> SemanticValue { SemanticValue::NumberBits(value.to_bits()) }
    #[test]
    fn preserved_header_encodings_and_order() {
        let values = [n(40.0), n(7.0), SemanticValue::Text(Arc::from(b"15x15".as_slice())), n(0.0), n(1.0)];
        let projected = project([("fps", &values[0]), ("cache_lifespan", &values[1]),
            ("view", &values[2]), ("visibility", &values[3]), ("visibility", &values[4])]).unwrap();
        assert_eq!(projected, vec![Directive::TickMilliseconds(25), Directive::CacheLifespan(7),
            Directive::View(0x0f0f), Directive::Flag{mask:0x2000,enabled:true},
            Directive::Flag{mask:0x2000,enabled:false}]);
    }
    #[test]
    fn invalid_values_are_never_defaulted_or_truncated() {
        assert!(project([("maxx", &n(1.5))]).is_err());
        assert!(project([("fps", &n(f32::NAN))]).is_err());
        assert!(project([("unknown", &SemanticValue::Null)]).is_err());
        assert_eq!(view(&SemanticValue::Text(Arc::from(b"0x10".as_slice()))).unwrap(), 5);
    }
}
