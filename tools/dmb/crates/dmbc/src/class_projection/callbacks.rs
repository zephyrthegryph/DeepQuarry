//! Derived VM callback dispatch flags, applied after source proc lists exist.
//! Masks are the pinned 516 class getters / FORMAT.md callback fixture receipts.
use super::{ClassProjection, ProjectionError};
use byond_dmb::dmb::Dmb;
use byond_dmb::ids::NONE;
use dm_ir::SymbolId;
use dm_link::LinkTables;
use std::collections::HashMap;

const EVENT: u64 = 0x800;
const MOVE: u64 = 0x80000;
const WHEEL: u64 = 0x100000;
const CALLBACKS: u64 = EVENT | MOVE | WHEEL;

fn callback_bits(name: SymbolId) -> u64 {
    if name == SymbolId::of("MouseEntered") || name == SymbolId::of("MouseExited") {
        EVENT
    } else if name == SymbolId::of("MouseMove") {
        // FORMAT.md's isolated callback table records MouseMove enabling both.
        MOVE | WHEEL
    } else if name == SymbolId::of("MouseWheel") {
        WHEEL
    } else {
        0
    }
}

/// Retained engine class flags are positive evidence; source proc chains add
/// authored handlers. Resolve actual parent IDs rather than lexical path prefixes.
/// No mutation occurs until every binding and parent chain has been validated.
pub fn materialize_callback_flags(
    dmb: &mut Dmb,
    projection: &ClassProjection,
    tables: &LinkTables,
) -> Result<(), ProjectionError> {
    let classes: HashMap<_, _> = dmb
        .classes
        .iter()
        .enumerate()
        .filter_map(|(i, c)| {
            dmb.string(c.path_string_id())
                .map(|p| (SymbolId::of_bytes(p), i))
        })
        .collect();
    let mut direct: Vec<_> = dmb.classes.iter().map(|c| c.flags & CALLBACKS).collect();
    for chain in projection.chains.iter().filter(|c| !c.verb) {
        let bits = callback_bits(chain.name);
        if bits == 0
            || chain.entries.is_empty()
            || chain.owner == SymbolId::of("/")
            || chain.owner == SymbolId::of("/world")
        {
            continue;
        }
        let &class = classes
            .get(&chain.owner)
            .ok_or(ProjectionError::MissingMember)?;
        let list = dmb
            .lists
            .get(dmb.classes[class].proc_list_id() as usize)
            .ok_or(ProjectionError::MissingMember)?;
        for key in chain.entries.iter() {
            let id = tables.index(*key).ok_or(ProjectionError::MissingMember)?;
            if dmb.procs.get(id as usize).is_none() || !list.contains(&id) {
                return Err(ProjectionError::Unsupported(
                    "callback chain absent from materialized owner proc list".into(),
                ));
            }
        }
        direct[class] |= bits;
    }
    let parents: Vec<_> = dmb.classes.iter().map(|c| c.parent_class_id()).collect();
    let effective = inherited_flags(&parents, &direct)?;
    for (class, bits) in dmb.classes.iter_mut().zip(effective) {
        class.flags = (class.flags & !CALLBACKS) | bits;
    }
    Ok(())
}

fn inherited_flags(parents: &[u32], direct: &[u64]) -> Result<Vec<u64>, ProjectionError> {
    let mut state = vec![0u8; parents.len()];
    let mut result = vec![0; parents.len()];
    for start in 0..parents.len() {
        if state[start] == 2 {
            continue;
        }
        let mut stack = Vec::new();
        let mut at = start;
        loop {
            if state[at] == 2 {
                break;
            }
            if state[at] == 1 {
                return Err(ProjectionError::Unsupported(
                    "cyclic callback class ancestry".into(),
                ));
            }
            state[at] = 1;
            stack.push(at);
            let parent = parents[at];
            if parent == NONE {
                break;
            }
            at = parent as usize;
            if at >= parents.len() {
                return Err(ProjectionError::MissingMember);
            }
        }
        for index in stack.into_iter().rev() {
            let parent = parents[index];
            result[index] = direct[index]
                | if parent == NONE {
                    0
                } else {
                    result[parent as usize]
                };
            state[index] = 2;
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_proven_callback_names_enable_known_bits() {
        assert_eq!(callback_bits(SymbolId::of("MouseEntered")), EVENT);
        assert_eq!(callback_bits(SymbolId::of("MouseExited")), EVENT);
        assert_eq!(callback_bits(SymbolId::of("MouseMove")), MOVE | WHEEL);
        assert_eq!(callback_bits(SymbolId::of("MouseWheel")), WHEEL);
        for name in ["MouseDown", "MouseDrop", "Click", "mousewheel"] {
            assert_eq!(callback_bits(SymbolId::of(name)), 0);
        }
    }
    #[test]
    fn forward_parents_and_inherited_callbacks_use_real_ancestry() {
        assert_eq!(
            inherited_flags(&[2, NONE, 1, 1], &[0, WHEEL, EVENT, 0]).unwrap(),
            vec![EVENT | WHEEL, WHEEL, EVENT | WHEEL, WHEEL]
        );
        assert_eq!(
            inherited_flags(&[NONE, 0], &[0, MOVE | WHEEL]).unwrap(),
            vec![0, MOVE | WHEEL]
        );
    }
    #[test]
    fn cycles_and_missing_parents_fail_closed() {
        assert!(inherited_flags(&[1, 0], &[0, 0]).is_err());
        assert!(inherited_flags(&[8], &[0]).is_err());
    }
    #[test]
    fn wheel_gap_matches_pinned_area_flags_and_getter() {
        assert_eq!(1062924u64 ^ 12300, WHEEL | EVENT);
        let dmb =
            Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
        let mut class = dmb.classes[0].clone();
        class.flags = 12300 | WHEEL | EVENT;
        assert!(class.has_mouse_wheel_proc());
        assert!(!class.has_mouse_move_proc());
        assert!(class.has_mouse_event_proc());
    }
}
