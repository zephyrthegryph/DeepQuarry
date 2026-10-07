//! Explicit client header ABI facts, separate from opaque variable metadata.
use dm_ir::SemanticValue;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Directive {
    Control(u16),
    Flag { mask: u32, enabled: bool },
    PreloadMode(u32),
    PreloadText,
    Script(crate::client_script::Script),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
    Invalid(String),
    Unsupported(String),
}

pub fn is_header_field(name: &str) -> bool {
    matches!(
        name,
        "control_freak" | "show_verb_panel" | "preload_rsc" | "script"
    )
}

/// Only authored values enter this projection. Omitted fields retain the
/// captured engine header; absence is not an implicit zero or null value.
pub fn project(name: &str, value: &SemanticValue) -> Result<Option<Directive>, Error> {
    if !is_header_field(name) {
        return Ok(None);
    }
    if name == "script" {
        return crate::client_script::project(value)
            .map(|script| Some(Directive::Script(script)))
            .map_err(Error::Unsupported);
    }
    if name == "preload_rsc" && matches!(value, SemanticValue::Text(_)) {
        return Ok(Some(Directive::PreloadText));
    }
    let SemanticValue::NumberBits(bits) = value else {
        return Err(Error::Invalid(format!("invalid client.{name}")));
    };
    let number = f32::from_bits(*bits);
    if !number.is_finite() {
        return Err(Error::Invalid(format!("invalid client.{name}")));
    }
    let directive = match name {
        "control_freak" if (0.0..=7.0).contains(&number) => Directive::Control(number as u16),
        "show_verb_panel" if number == 0.0 || number == 1.0 => Directive::Flag {
            mask: 0x400,
            enabled: number == 0.0,
        },
        "preload_rsc" if (0.0..=2.0).contains(&number) => {
            // Native 0.5 and 1.5 fixtures select the ordinary mode. This is
            // equality against the scalar value, not truncation to an integer.
            Directive::PreloadMode(if number == 0.0 {
                0x800
            } else if number == 2.0 {
                0x1000
            } else {
                0
            })
        }
        _ => return Err(Error::Invalid(format!("invalid client.{name}"))),
    };
    Ok(Some(directive))
}

pub fn apply(dmb: &mut byond_dmb::dmb::Dmb, directives: &[Directive]) {
    for directive in directives {
        match directive {
            Directive::Control(value) => dmb.world.control = *value,
            Directive::Flag { mask, enabled } => {
                if *enabled {
                    dmb.header.flags |= *mask;
                } else {
                    dmb.header.flags &= !*mask;
                }
            }
            Directive::PreloadMode(bits) => {
                dmb.header.flags = (dmb.header.flags & !0x1800) | *bits;
            }
            Directive::PreloadText => {
                dmb.header.flags = (dmb.header.flags & !0x1800) | 0x800;
            }
            // Script is applied by the bound writer after final selection.
            Directive::Script(_) => {}
        }
    }
}

/// Native configuration visits descendants before ancestors, preserving
/// first-created sibling order. The caller supplies certified class creation
/// ordinals; no symbol hash or lexical path sort stands in for allocation.
pub fn configuration_order(
    root: dm_ir::SymbolId,
    types: &[(dm_ir::SymbolId, Option<dm_ir::SymbolId>, u32)],
) -> Result<Vec<dm_ir::SymbolId>, Error> {
    use std::collections::{HashMap, HashSet};
    let mut children = HashMap::<_, Vec<_>>::new();
    let mut present = HashSet::new();
    for &(path, parent, ordinal) in types {
        if !present.insert(path) {
            return Err(Error::Unsupported(
                "duplicate client configuration type".into(),
            ));
        }
        if let Some(parent) = parent {
            children.entry(parent).or_default().push((ordinal, path));
        }
    }
    if !present.contains(&root) {
        return Ok(Vec::new());
    }
    for children in children.values_mut() {
        children.sort_by_key(|&(ordinal, _)| ordinal);
    }
    fn visit(
        path: dm_ir::SymbolId,
        children: &HashMap<dm_ir::SymbolId, Vec<(u32, dm_ir::SymbolId)>>,
        seen: &mut HashSet<dm_ir::SymbolId>,
        output: &mut Vec<dm_ir::SymbolId>,
    ) -> Result<(), Error> {
        if !seen.insert(path) {
            return Err(Error::Unsupported("client hierarchy cycle".into()));
        }
        if let Some(children_here) = children.get(&path) {
            for &(_, child) in children_here {
                visit(child, children, seen, output)?;
            }
        }
        output.push(path);
        Ok(())
    }
    let mut output = Vec::new();
    visit(root, &children, &mut HashSet::new(), &mut output)?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn number(value: f32) -> SemanticValue {
        SemanticValue::NumberBits(value.to_bits())
    }
    #[test]
    fn native_fraction_and_disabled_panel_facts() {
        assert_eq!(
            project("control_freak", &number(3.5)),
            Ok(Some(Directive::Control(3)))
        );
        assert_eq!(
            project("preload_rsc", &number(0.5)),
            Ok(Some(Directive::PreloadMode(0)))
        );
        assert_eq!(
            project("preload_rsc", &number(2.0)),
            Ok(Some(Directive::PreloadMode(0x1000)))
        );
        assert_eq!(
            project("show_verb_panel", &number(0.0)),
            Ok(Some(Directive::Flag {
                mask: 0x400,
                enabled: true
            }))
        );
        assert!(project("control_freak", &number(8.0)).is_err());
        assert_eq!(project("unrecognized", &SemanticValue::Null), Ok(None));
    }
    #[test]
    fn native_preload_controls_and_text_preserve_header_modes() {
        use byond_dmb::dmb::Dmb;
        let controls: &[(&[u8], SemanticValue)] = &[
            (include_bytes!("../../../fixtures/translation/client_header_probe/preload0.native.bin"), number(0.0)),
            (include_bytes!("../../../fixtures/translation/client_header_probe/preload1.native.bin"), number(1.0)),
            (include_bytes!("../../../fixtures/translation/client_header_probe/preload2.native.bin"), number(2.0)),
            (include_bytes!("../../../fixtures/translation/client_header_probe/preload_fraction.native.bin"), number(0.5)),
            (include_bytes!("../../../fixtures/translation/client_header_probe/preload_three_halves.native.bin"), number(1.5)),
            (include_bytes!("../../../fixtures/translation/client_header_probe/preload_text.native.bin"), SemanticValue::Text(std::sync::Arc::from(b"download.rsc".as_slice()))),
        ];
        for (bytes, value) in controls {
            let expected = Dmb::from_bytes(bytes).unwrap();
            let mut actual = expected.clone();
            actual.header.flags ^= 0x1800;
            apply(
                &mut actual,
                &[project("preload_rsc", value).unwrap().unwrap()],
            );
            assert_eq!(actual.header.flags, expected.header.flags);
        }
    }
    #[test]
    fn native_configuration_order_uses_creation_not_spelling() {
        use dm_ir::SymbolId;
        let root = SymbolId::of("/client");
        let first = SymbolId::of("/client/z");
        let second = SymbolId::of("/client/a");
        let nested = SymbolId::of("/client/z/nested");
        assert_eq!(
            configuration_order(
                root,
                &[
                    (root, None, 9),
                    (second, Some(root), 8),
                    (nested, Some(first), 5),
                    (first, Some(root), 6),
                ]
            )
            .unwrap(),
            vec![nested, first, second, root]
        );
    }
}
