//! Preserve the exact legacy field order/framing while in-memory owners share.
use super::*;
#[derive(Serialize)]
struct Borrowed<'a> {
    version: u32,
    policy: u128,
    catalog: &'a CatalogRecord,
    catalog_identity: u128,
    inputs: &'a InputSnapshot,
    order: &'a Vec<usize>,
    archive: ResourceIdentity,
}
#[derive(Deserialize)]
struct Owned {
    version: u32,
    policy: u128,
    catalog: CatalogRecord,
    catalog_identity: u128,
    inputs: InputSnapshot,
    order: Vec<usize>,
    archive: ResourceIdentity,
}
impl Serialize for ResourceManifest {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        Borrowed {
            version: self.version,
            policy: self.policy,
            catalog: &self.catalog,
            catalog_identity: self.catalog_identity,
            inputs: &self.inputs,
            order: &self.content.order,
            archive: self.content.archive,
        }
        .serialize(serializer)
    }
}
impl<'de> Deserialize<'de> for ResourceManifest {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = Owned::deserialize(deserializer)?;
        Ok(Self {
            version: value.version,
            policy: value.policy,
            catalog: Arc::new(value.catalog),
            catalog_identity: value.catalog_identity,
            inputs: Arc::new(value.inputs),
            content: Arc::new(ResourceContent {
                order: value.order,
                archive: value.archive,
            }),
            admitted_catalog: OnceLock::new(),
        })
    }
}
