//! Immutable shared source roster; certificates still compare exact values.
use super::{DebugOrigin, DebugOrigins};
use crate::symbolic::origin_roster::OriginRoster;
use std::{collections::HashMap, sync::Arc};
#[derive(Clone, Copy, Debug)]
pub struct DebugOriginView<'a> {
    pub semantic_path: &'a Arc<str>,
    pub line: u32,
}
pub trait OriginAccess {
    fn iter(&self) -> impl Iterator<Item = DebugOriginView<'_>>;
}
impl<T: OriginAccess> OriginAccess for Arc<T> {
    fn iter(&self) -> impl Iterator<Item = DebugOriginView<'_>> {
        self.as_ref().iter()
    }
}
impl OriginAccess for DebugOrigins {
    fn iter(&self) -> impl Iterator<Item = DebugOriginView<'_>> {
        self.entries.iter().map(|origin| DebugOriginView {
            semantic_path: &origin.semantic_path,
            line: origin.line,
        })
    }
}
#[derive(Debug)]
struct Storage {
    paths: Box<[Arc<str>]>,
    origins: OriginRoster,
}
#[derive(Clone, Debug)]
pub struct FrozenDebugOrigins(Arc<Storage>);
impl Default for FrozenDebugOrigins {
    fn default() -> Self {
        DebugOrigins::default().into()
    }
}
impl From<DebugOrigins> for FrozenDebugOrigins {
    fn from(origins: DebugOrigins) -> Self {
        let mut paths = Vec::new();
        let mut indexes = HashMap::new();
        let roster = OriginRoster::from_entries(origins.entries.into_iter().map(|origin| {
            let next = paths.len();
            let index = *indexes
                .entry(Arc::clone(&origin.semantic_path))
                .or_insert_with(|| {
                    paths.push(origin.semantic_path);
                    next
                });
            (index, origin.line)
        }));
        Self(Arc::new(Storage {
            paths: paths.into_boxed_slice(),
            origins: roster,
        }))
    }
}
impl From<Arc<DebugOrigins>> for FrozenDebugOrigins {
    fn from(origins: Arc<DebugOrigins>) -> Self {
        let mut paths = Vec::new();
        let mut indexes = HashMap::new();
        let roster = OriginRoster::from_entries(origins.entries.iter().map(|origin| {
            let next = paths.len();
            let index = *indexes
                .entry(Arc::clone(&origin.semantic_path))
                .or_insert_with(|| {
                    paths.push(Arc::clone(&origin.semantic_path));
                    next
                });
            (index, origin.line)
        }));
        Self(Arc::new(Storage {
            paths: paths.into_boxed_slice(),
            origins: roster,
        }))
    }
}
impl OriginAccess for FrozenDebugOrigins {
    fn iter(&self) -> impl Iterator<Item = DebugOriginView<'_>> {
        self.0.origins.iter().map(|(path, line)| DebugOriginView {
            semantic_path: &self.0.paths[path],
            line,
        })
    }
}
impl FrozenDebugOrigins {
    pub fn len(&self) -> usize {
        self.0.origins.len()
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn source_bindings(&self) -> dm_link::SourceBindings {
        let mut result = dm_link::SourceBindings::default();
        for (ordinal, origin) in self.iter().enumerate() {
            let ordinal = u32::try_from(ordinal).expect("collector bounds ordinals");
            result
                .files
                .insert(ordinal, dm_ir::SymbolId::of(origin.semantic_path));
            result.lines.insert(ordinal, origin.line);
        }
        result
    }
    pub fn to_owned_origins(&self) -> DebugOrigins {
        DebugOrigins {
            entries: self
                .iter()
                .map(|origin| DebugOrigin {
                    semantic_path: Arc::clone(origin.semantic_path),
                    line: origin.line,
                })
                .collect(),
        }
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus, owner: &str) {
        if census.arc_object(owner, &self.0) {
            census.slice(owner, &self.0.paths, true);
            self.0.origins.census(census);
            for path in &self.0.paths {
                census.arc_text(owner, path);
            }
        }
    }
}
impl dm_link::SourceBindingAccess for FrozenDebugOrigins {
    fn first_line(&self) -> u32 {
        0
    }
    fn line(&self, ordinal: u32) -> Option<u32> {
        let index = usize::try_from(ordinal).ok()?;
        self.0.origins.get(index).map(|(_, line)| line)
    }
    fn file(&self, ordinal: u32) -> Option<dm_ir::SymbolId> {
        let index = usize::try_from(ordinal).ok()?;
        let (path, _) = self.0.origins.get(index)?;
        self.0.paths.get(path).map(|path| dm_ir::SymbolId::of(path))
    }
}
impl PartialEq for FrozenDebugOrigins {
    fn eq(&self, other: &Self) -> bool {
        self.len() == other.len()
            && self
                .iter()
                .zip(other.iter())
                .all(|(a, b)| a.line == b.line && a.semantic_path == b.semantic_path)
    }
}
impl Eq for FrozenDebugOrigins {}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_roster_preserves_exact_source_values_and_detects_rebinding() {
        let raw = DebugOrigins {
            entries: vec![
                DebugOrigin {
                    semantic_path: Arc::from("a.dm"),
                    line: 1,
                },
                DebugOrigin {
                    semantic_path: Arc::from("a.dm"),
                    line: u32::MAX,
                },
            ],
        };
        let bindings = raw.source_bindings();
        let frozen: FrozenDebugOrigins = raw.into();
        let snapshot = frozen.clone();
        assert!(Arc::ptr_eq(&frozen.0, &snapshot.0));
        assert_eq!(bindings.files, frozen.source_bindings().files);
        assert_eq!(bindings.lines, frozen.source_bindings().lines);
        let mut moved = frozen.to_owned_origins();
        moved.entries[1].line -= 1;
        assert_ne!(frozen, FrozenDebugOrigins::from(moved));
        assert_eq!(snapshot.source_bindings().files, bindings.files);
        assert_eq!(snapshot.source_bindings().lines, bindings.lines);
    }
    #[test]
    fn borrowed_origin_binding_matches_maps_and_preserves_missing_error_order() {
        use dm_ir::{Relocation, RelocationEncoding, SymRef, SymbolId, SymbolicCode};
        let path = "unicode/雪.dm";
        let origins: FrozenDebugOrigins = DebugOrigins {
            entries: vec![
                DebugOrigin {
                    semantic_path: Arc::from(path),
                    line: 7,
                },
                DebugOrigin {
                    semantic_path: Arc::from(path),
                    line: u32::MAX,
                },
            ],
        }
        .into();
        let id = SymbolId::of(path);
        let tables = dm_link::LinkTables::build(dm_link::LinkInventory {
            entries: vec![dm_link::Entry {
                key: dm_link::Key::String(id),
                content: path.as_bytes().to_vec().into(),
            }],
            spellings: vec![(id, Arc::from(path.as_bytes()))],
            ..Default::default()
        })
        .unwrap();
        let code = |references: &[SymRef]| {
            SymbolicCode::new(
                vec![0; references.len()],
                references
                    .iter()
                    .enumerate()
                    .map(|(offset, &reference)| Relocation {
                        offset: offset as u32,
                        reference,
                        encoding: RelocationEncoding::Direct,
                    })
                    .collect(),
            )
            .unwrap()
        };
        let mixed = code(&[
            SymRef::SourceFile(0),
            SymRef::SourceLine(1),
            SymRef::LineDelta(5),
            SymRef::SourceFile(0),
        ]);
        let map = origins.source_bindings();
        assert_eq!(
            tables.link_from(&mixed, &origins).unwrap(),
            tables.link(&mixed, &map).unwrap()
        );
        let missing = code(&[SymRef::SourceLine(2), SymRef::Type(SymbolId::of("/absent"))]);
        assert_eq!(
            tables.link_from(&missing, &origins),
            Err(dm_link::LinkError::MissingSourceLine(2))
        );
        let missing_file = code(&[SymRef::SourceFile(u32::MAX)]);
        assert_eq!(
            tables.link_from(&missing_file, &origins),
            Err(dm_link::LinkError::MissingSourceFile(u32::MAX))
        );
        assert_eq!(
            dm_link::SourceBindingAccess::line(&origins, 1),
            Some(u32::MAX)
        );
        assert_eq!(dm_link::SourceBindingAccess::line(&origins, u32::MAX), None);
        let mut shifted = origins.to_owned_origins();
        shifted.entries[1].line = 99;
        let shifted: FrozenDebugOrigins = shifted.into();
        assert_eq!(
            tables.link_from(&mixed, &shifted).unwrap(),
            tables.link(&mixed, &shifted.source_bindings()).unwrap()
        );
        assert_ne!(
            tables.link_from(&mixed, &origins).unwrap(),
            tables.link_from(&mixed, &shifted).unwrap()
        );
    }
}
