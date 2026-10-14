//! Single supported header inheritance catalog: selection and wire writes share it.
use super::{Class, ProjectionError};
pub(crate) struct HeaderField {
    pub name: &'static str,
    pub copy: fn(&Class, &mut Class) -> Result<(), ProjectionError>,
}
macro_rules! fields {
    ($($name:literal => |$parent:ident, $child:ident| $body:block),* $(,)?) => {
        pub(crate) const FIELDS: &[HeaderField] = &[$(HeaderField {
            name: $name,
            copy: |$parent, $child| { $body; Ok(()) },
        }),*];
    };
}
fields! {
    "desc" => |p, c| { c.initial_ids[3] = p.initial_ids[3] },
    "icon" => |p, c| { c.initial_ids[4] = p.initial_ids[4] },
    "icon_state" => |p, c| { c.initial_ids[5] = p.initial_ids[5] },
    "name" => |p, c| { c.initial_ids[2] = p.initial_ids[2] },
    "text" => |p, c| { c.text = p.text },
    "layer" => |p, c| { c.layer_bits = p.layer_bits },
    "dir" => |p, c| { c.direction = p.direction },
    "maptext" => |p, c| { c.maptext = p.maptext },
    "suffix" => |p, c| { c.suffix = p.suffix },
    "maptext_width" => |p, c| { c.maptext_geometry[0] = p.maptext_geometry[0] },
    "maptext_height" => |p, c| { c.maptext_geometry[1] = p.maptext_geometry[1] },
    "maptext_x" => |p, c| { c.maptext_geometry[2] = p.maptext_geometry[2] },
    "maptext_y" => |p, c| { c.maptext_geometry[3] = p.maptext_geometry[3] },
    "transform" => |p, c| { c.transform_flag = p.transform_flag; c.transform = p.transform },
    "invisibility" => |p, c| { c.set_normally_visible(p.is_normally_visible()); },
    "gender" => |p, c| { c.set_gender_code(p.gender_code()).map_err(|e| ProjectionError::Unsupported(e.to_string()))?; },
    "density" => |p, c| { c.set_dense(p.is_dense()); },
    "opacity" => |p, c| { c.set_opaque(p.is_opaque()); },
    "appearance_flags" => |p, c| { c.set_appearance_flags(p.appearance_flags()); },
    "luminosity" => |p, c| { c.set_luminosity(p.luminosity()).map_err(|e| ProjectionError::Unsupported(e.to_string()))?; },
    "mouse_opacity" => |p, c| { c.set_mouse_opacity(p.mouse_opacity()).map_err(|e| ProjectionError::Unsupported(e.to_string()))?; },
    "animate_movement" => |p, c| { c.set_animate_movement(p.animate_movement()).map_err(|e| ProjectionError::Unsupported(e.to_string()))?; },
}
