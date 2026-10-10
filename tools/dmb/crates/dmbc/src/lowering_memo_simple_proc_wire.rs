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
    )
        .serialize(serializer)
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
    })
}
