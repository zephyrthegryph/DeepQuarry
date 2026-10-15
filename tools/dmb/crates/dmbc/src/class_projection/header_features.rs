//! Pinned 516.1687 callback negotiation header facts.
//! CLIENT_HEADER_PROBES.md and translation/client_header_probe native pairs
//! distinguish atom/client callbacks from unrelated same-spelled procedures.
use super::ProjectionError;
use byond_dmb::{dmb::Dmb, ids::NONE};
use dm_ir::SymbolId;
use std::collections::HashMap;

#[derive(Default)]
pub(super) struct HeaderFeatures {
    flags: u32,
    extended: u32,
    /// Built-in variable defaults priced by the minimum-client line, one unit per authored class.
    compat_units: HashMap<usize, dm_ir::header_compat::UnitCompat>,
}
impl HeaderFeatures {
    pub(super) fn recognizes(name: SymbolId) -> bool {
        callback(name, true) != (0, 0)
    }
    pub(super) fn observe(
        &mut self,
        name: SymbolId,
        class: usize,
        parents: &[u32],
        classes: &HashMap<SymbolId, usize>,
    ) -> Result<(), ProjectionError> {
        let inherits = |owner| inherits(owner, class, parents, classes);
        let client = inherits("/client")?;
        if !client && !inherits("/atom")? {
            return Ok(());
        }
        let (flags, extended) = callback(name, client);
        self.flags |= flags;
        self.extended |= extended;
        Ok(())
    }
    pub(super) fn observe_graphics(
        &mut self,
        class: usize,
        parents: &[u32],
        classes: &HashMap<SymbolId, usize>,
    ) -> Result<(), ProjectionError> {
        for root in [
            "/atom",
            "/obj",
            "/mob",
            "/turf",
            "/area",
            "/image",
            "/mutable_appearance",
        ] {
            if inherits(root, class, parents, classes)? {
                self.flags |= 0x40;
                return Ok(());
            }
        }
        Ok(())
    }
    /// An authored default for a built-in variable (`/obj/plane = 5`). `class` is the owner's class index.
    pub(super) fn observe_default(
        &mut self,
        name: SymbolId,
        class: usize,
        parents: &[u32],
        classes: &HashMap<SymbolId, usize>,
    ) -> Result<(), ProjectionError> {
        use dm_ir::header_compat::Family;
        let family = if inherits("/client", class, parents, classes)? {
            Family::Client
        } else if inherits("/world", class, parents, classes)? {
            Family::World
        } else if ["/atom", "/image", "/mutable_appearance"]
            .into_iter()
            .try_fold(false, |found, root| {
                Ok::<_, ProjectionError>(found || inherits(root, class, parents, classes)?)
            })?
        {
            Family::Atom
        } else {
            return Ok(());
        };
        self.compat_units
            .entry(class)
            .or_default()
            .note_default(family, name);
        Ok(())
    }
    pub(super) fn apply(self, dmb: &mut Dmb) {
        let mut compat = dm_ir::header_compat::HeaderCompat::default();
        for unit in self.compat_units.values() {
            compat.union(unit.seal());
        }
        crate::header_compat::apply(dmb, compat);
        // Captured engine bits remain authoritative; only current authored
        // definitions add negotiation requirements. No old generation is read.
        dmb.header.flags |= self.flags & !0x40;
        if self.flags & 0x40 != 0 {
            dmb.header.flags &= !0x40;
        }
        if self.extended != 0 {
            dmb.header.extended_flags =
                Some(dmb.header.extended_flags.unwrap_or(0) | self.extended);
        }
    }
}
fn inherits(
    owner: &str,
    class: usize,
    parents: &[u32],
    classes: &HashMap<SymbolId, usize>,
) -> Result<bool, ProjectionError> {
    let Some(&root) = classes.get(&SymbolId::of(owner)) else {
        return Ok(false);
    };
    let mut at = class;
    for _ in 0..parents.len() {
        if at == root {
            return Ok(true);
        }
        let parent = *parents.get(at).ok_or(ProjectionError::MissingMember)?;
        if parent == NONE {
            return Ok(false);
        }
        at = parent as usize;
    }
    Err(ProjectionError::Unsupported(
        "cyclic header feature ancestry".into(),
    ))
}
fn callback(name: SymbolId, client: bool) -> (u32, u32) {
    for (spelling, flags) in [
        ("Click", 0x4),
        ("DblClick", 0x8),
        ("MouseUp", 0x0020_0000),
        ("MouseDown", 0x0040_0000),
        ("MouseDrop", 0x0080_0000),
        ("MouseDrag", 0x0100_0000),
    ] {
        if name == SymbolId::of(spelling) {
            return (flags, 0);
        }
    }
    if client {
        for (spelling, flags, extended) in [
            ("MouseEntered", 0x0200_0000, 0),
            ("MouseExited", 0x0200_0000, 0),
            ("MouseMove", 0x8200_0000, 1),
            ("MouseWheel", 0x8000_0000, 2),
            ("Command", 0x4000, 0),
            ("IsByondMember", 0x0004_0000, 0),
        ] {
            if name == SymbolId::of(spelling) {
                return (flags, extended);
            }
        }
    }
    (0, 0)
}

#[cfg(test)]
#[path = "header_features_tests.rs"]
mod tests;
