//! Resource scalar binding uses the same captured search domain as codegen.
//! Dense IDs are supplied exclusively by the frozen linker inventory.
use crate::class_projection::ProjectionError;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId};

pub fn key(
    resolver: &dyn Resolver,
    path: SymbolId,
    search_context: u128,
) -> Result<dm_link::Key, ProjectionError> {
    let query = ResolveQuery::ResourceIn { path, search_context };
    match resolver.resolve(query) {
        ResolvedMeaning::Resource { content, .. } => Ok(dm_link::Key::Resource(content)),
        ResolvedMeaning::Missing => Err(ProjectionError::Unsupported(
            "resource scalar has a captured negative lookup".into(),
        )),
        ResolvedMeaning::Unsupported(_) => Err(ProjectionError::Unsupported(
            "resource scalar search domain is not captured".into(),
        )),
        _ => Err(ProjectionError::Unsupported(
            "resource scalar resolver returned a different semantic domain".into(),
        )),
    }
}

pub struct CapturedResourceValues<'a> {
    types: &'a dyn crate::class_projection::TypeValuePolicy,
    resolver: &'a dyn Resolver,
    search_context: u128,
}
impl<'a> CapturedResourceValues<'a> {
    pub fn new(
        types: &'a dyn crate::class_projection::TypeValuePolicy,
        resolver: &'a dyn Resolver,
        search_context: u128,
    ) -> Self { Self { types, resolver, search_context } }
}
impl crate::class_projection::TypeValuePolicy for CapturedResourceValues<'_> {
    fn tag(&self, path: SymbolId) -> Result<u8, ProjectionError> { self.types.tag(path) }
    fn mob_index(&self, path: SymbolId) -> Result<u32, ProjectionError> { self.types.mob_index(path) }
    fn resource_key(&self, path: SymbolId) -> Result<dm_link::Key, ProjectionError> {
        key(self.resolver, path, self.search_context)
    }
}

pub fn index(
    resolver: &dyn Resolver,
    path: SymbolId,
    search_context: u128,
    tables: &dm_link::LinkTables,
) -> Result<u32, ProjectionError> {
    let key = key(resolver, path, search_context)?;
    tables.index(key).ok_or_else(|| ProjectionError::Unsupported(
        "captured resource content is absent from frozen resource inventory".into(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_link::{Entry, Key, LinkInventory, LinkTables, Table};
    use std::sync::Arc;
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::ResourceIn { path, search_context: 7 }
                    if path == SymbolId::of("literal-name.dmi") =>
                    ResolvedMeaning::Resource { path: SymbolId::of("icons/gen/actual.dmi"), content: 42 },
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    #[test]
    fn qualified_alias_binds_content_to_frozen_resource_domain() {
        let mut inventory = LinkInventory::default();
        inventory.entries.push(Entry { key: Key::Resource(42), content: Arc::from(b"exact asset".as_slice()) });
        inventory.reserved_prefixes.insert(Table::Resource, 5);
        let tables = LinkTables::build(inventory).unwrap();
        let literal = SymbolId::of("literal-name.dmi");
        assert_eq!(key(&Host, literal, 7).unwrap(), Key::Resource(42));
        assert_eq!(index(&Host, literal, 7, &tables).unwrap(), 5);
        assert!(index(&Host, literal, 8, &tables).is_err());
        assert!(index(&Host, SymbolId::of("absent.dmi"), 7, &tables).is_err());
        assert!(index(&Host, literal, 7, &LinkTables::build(Default::default()).unwrap()).is_err());
    }
}
