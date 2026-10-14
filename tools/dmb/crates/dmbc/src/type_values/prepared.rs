//! Compact authoritative emission domains; no source tree or resolver retained.
use super::*;
use crate::{class_projection::ClassProjection, initializer_policy::DefaultValue};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Default)]
pub struct PreparedValueDomains {
    types: BTreeSet<SymbolId>,
    resources: BTreeSet<SymbolId>,
}
impl PreparedValueDomains {
    pub fn for_projection(projection: &ClassProjection) -> Self {
        let mut domains = Self::default();
        for value in projection.types.iter() {
            domains.include_type(value.path);
        }
        for value in projection.fields.iter().map(|field| &field.value).chain(
            projection
                .procedure_statics
                .iter()
                .map(|field| &field.value),
        ) {
            if let DefaultValue::Scalar(value) = value {
                domains.include_value(value);
            }
        }
        domains
    }
    pub fn include_type(&mut self, path: SymbolId) {
        self.types.insert(path);
    }
    pub fn include_resource(&mut self, path: SymbolId) {
        self.resources.insert(path);
    }
    pub fn include_value(&mut self, value: &dm_ir::SemanticValue) {
        // Iterative traversal keeps arbitrary nested constant lists off the stack.
        let mut pending = vec![value];
        while let Some(value) = pending.pop() {
            match value {
                dm_ir::SemanticValue::Type(path) => self.include_type(*path),
                dm_ir::SemanticValue::Resource(path) => self.include_resource(*path),
                dm_ir::SemanticValue::ModifiedInstance(instance) => {
                    self.include_type(instance.runtime_type());
                    for resource in instance.resources().values() {
                        self.include_resource(resource.path);
                    }
                }
                dm_ir::SemanticValue::List(entries) => {
                    for (key, value) in entries.iter() {
                        if let Some(key) = key {
                            pending.push(key);
                        }
                        pending.push(value);
                    }
                }
                _ => (),
            }
        }
    }
    pub fn types(&self) -> impl Iterator<Item = SymbolId> + '_ {
        self.types.iter().copied()
    }
    pub fn resources(&self) -> impl Iterator<Item = SymbolId> + '_ {
        self.resources.iter().copied()
    }
}

pub struct PreparedTypeValues {
    tags: BTreeMap<SymbolId, Result<u8, ProjectionError>>,
    mobs: BTreeMap<SymbolId, Result<u32, ProjectionError>>,
}
impl PreparedTypeValues {
    /// Retain negative authoritative answers until actually requested, preserving
    /// diagnostics for admitted types that never appear as encoded values.
    pub fn capture(policy: &dyn TypeValuePolicy, domains: &PreparedValueDomains) -> Self {
        Self {
            mobs: domains
                .types()
                .map(|path| (path, policy.mob_index(path)))
                .collect(),
            tags: domains
                .types()
                .map(|path| (path, policy.tag(path)))
                .collect(),
        }
    }
}
impl TypeValuePolicy for PreparedTypeValues {
    fn mob_index(&self, path: SymbolId) -> Result<u32, ProjectionError> {
        self.mobs.get(&path).cloned().unwrap_or_else(|| {
            Err(ProjectionError::Unsupported(
                "mob index is absent from prepared emission domain".into(),
            ))
        })
    }
    fn tag(&self, path: SymbolId) -> Result<u8, ProjectionError> {
        self.tags.get(&path).cloned().unwrap_or_else(|| {
            Err(ProjectionError::Unsupported(
                "runtime type is absent from prepared emission domain".into(),
            ))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::SemanticValue;
    struct Policy;
    impl TypeValuePolicy for Policy {
        fn mob_index(&self, path: SymbolId) -> Result<u32, ProjectionError> {
            if path == SymbolId::of("/datum/redirected") {
                Ok(137)
            } else {
                Err(ProjectionError::Unsupported("mob negative".into()))
            }
        }
        fn resource_index(&self, path: SymbolId) -> Result<u32, ProjectionError> {
            if path == SymbolId::of("captured.dmi") {
                Ok(271)
            } else {
                Err(ProjectionError::Unsupported("index negative".into()))
            }
        }
        fn tag(&self, path: SymbolId) -> Result<u8, ProjectionError> {
            if path == SymbolId::of("/datum/redirected") {
                Ok(8)
            } else {
                Err(ProjectionError::Unsupported(
                    "authoritative negative".into(),
                ))
            }
        }
        fn resource_key(&self, path: SymbolId) -> Result<dm_link::Key, ProjectionError> {
            if path == SymbolId::of("captured.dmi") {
                Ok(dm_link::Key::Resource(71))
            } else {
                Err(ProjectionError::Unsupported("resource negative".into()))
            }
        }
    }
    #[test]
    fn owned_answers_cover_nested_keys_and_preserve_negatives_without_guessing() {
        let path = SymbolId::of("/datum/redirected");
        let resource = SymbolId::of("captured.dmi");
        let missing = SymbolId::of("/unknown");
        let mut domains = PreparedValueDomains::default();
        domains.include_value(&SemanticValue::List(std::sync::Arc::from([(
            Some(SemanticValue::Type(path)),
            SemanticValue::List(std::sync::Arc::from([(
                None,
                SemanticValue::Resource(resource),
            )])),
        )])));
        domains.include_type(missing);
        let owned = crate::resource_values::PreparedResourceValues::capture(&Policy, &domains);
        assert_eq!(owned.tag(path).unwrap(), 8);
        assert_eq!(owned.mob_index(path), Policy.mob_index(path));
        assert_eq!(
            owned.resource_index(resource),
            Policy.resource_index(resource)
        );
        assert_eq!(owned.mob_index(missing), Policy.mob_index(missing));
        assert!(owned.mob_index(SymbolId::of("unissued")).is_err());
        assert!(owned.resource_index(SymbolId::of("unissued.dmi")).is_err());
        assert_eq!(
            owned.resource_key(resource).unwrap(),
            dm_link::Key::Resource(71)
        );
        assert_eq!(owned.tag(missing), Policy.tag(missing));
        assert!(owned
            .tag(SymbolId::of("/datum/redirected/not-issued"))
            .is_err());
        assert!(owned
            .resource_key(SymbolId::of("captured-other.dmi"))
            .is_err());
        fn is_static(_: Box<dyn TypeValuePolicy + 'static>) {}
        is_static(Box::new(owned));
    }
    #[test]
    fn prepared_resource_rejects_an_authoritative_answer_in_wrong_domain() {
        struct Wrong;
        impl TypeValuePolicy for Wrong {
            fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
                Ok(32)
            }
            fn resource_key(&self, path: SymbolId) -> Result<dm_link::Key, ProjectionError> {
                Ok(dm_link::Key::Type(path))
            }
        }
        let path = SymbolId::of("wrong.dmi");
        let mut domains = PreparedValueDomains::default();
        domains.include_resource(path);
        let owned = crate::resource_values::PreparedResourceValues::capture(&Wrong, &domains);
        assert!(owned.resource_key(path).is_err());
    }
}
