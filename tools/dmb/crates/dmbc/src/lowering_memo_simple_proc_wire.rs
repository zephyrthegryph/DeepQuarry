//! Complete positional binary representation of SimpleProc. Its public serde
//! representation omits empty diagnostics for JSON; binary records cannot omit
//! a field because the next field would be decoded in its place.
use dm_codegen_byond::{ProcedureWarning, SimpleProc, StringPayload, SymbolicProc};
use dm_ir::SymbolId;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub(super) fn serialize<S: Serializer>(
    value: &SimpleProc,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    (
        &value.warnings,
        &value.code,
        &value.strings,
        &value.class_paths,
        &value.instance_paths,
        &value.resources,
        value.local_count,
        &value.local_names,
        &value.argument_names,
        &value.argument_type_flags,
        &value.argument_value_sources,
        value.source_features,
    )
        .serialize(serializer)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Serialize, Deserialize)]
    struct Wire(#[serde(with = "super")] SimpleProc);

    #[test]
    fn positional_source_features_roundtrip_and_featureless_payload_declines() {
        const SCHEMA: u32 = 0x0f25_0001;
        for features in [
            dm_codegen_byond::SourceFeatures::default(),
            dm_codegen_byond::SourceFeatures {
                world_cpu: true,
                native_graphics: false,
            },
            dm_codegen_byond::SourceFeatures {
                world_cpu: false,
                native_graphics: true,
            },
            dm_codegen_byond::SourceFeatures {
                world_cpu: true,
                native_graphics: true,
            },
        ] {
            let value = SimpleProc {
                source_features: features,
                ..Default::default()
            };
            let bytes = dm_wire::encode(SCHEMA, &Wire(value.clone())).unwrap();
            let decoded: Wire = dm_wire::decode(SCHEMA, &bytes, bytes.len()).unwrap();
            assert_eq!(decoded.0, value);
            // Exact old positional format has no feature authority. It cannot
            // silently receive the public JSON compatibility default.
            let old = (
                &value.warnings,
                &value.code,
                &value.strings,
                &value.class_paths,
                &value.instance_paths,
                &value.resources,
                value.local_count,
                &value.local_names,
                &value.argument_names,
                &value.argument_type_flags,
                &value.argument_value_sources,
            );
            let old = dm_wire::encode(SCHEMA, &old).unwrap();
            assert!(dm_wire::decode::<Wire>(SCHEMA, &old, old.len()).is_err());
        }
    }
}

pub(super) fn deserialize<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<SimpleProc, D::Error> {
    type Fields = (
        Vec<ProcedureWarning>,
        SymbolicProc,
        Vec<StringPayload>,
        Vec<SymbolId>,
        Vec<SymbolId>,
        Vec<u128>,
        u32,
        Vec<String>,
        Vec<String>,
        Vec<u32>,
        Vec<u32>,
        dm_codegen_byond::SourceFeatures,
    );
    let (
        warnings,
        code,
        strings,
        class_paths,
        instance_paths,
        resources,
        local_count,
        local_names,
        argument_names,
        argument_type_flags,
        argument_value_sources,
        source_features,
    ) = Fields::deserialize(deserializer)?;
    Ok(SimpleProc {
        warnings,
        code,
        strings,
        class_paths,
        instance_paths,
        resources,
        local_count,
        local_names,
        argument_names,
        argument_type_flags,
        argument_value_sources,
        source_features,
    })
}
