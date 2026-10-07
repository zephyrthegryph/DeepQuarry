//! Compatibility entry point during the semantic-tree extraction. The scalar
//! evaluator is owned by dm-tree; literal decoding remains the preserved codec.

pub(super) use dm_tree::constants::Constant;

pub(super) fn evaluate(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
) -> Option<Constant> {
    dm_tree::constants::evaluate_with(
        source,
        resolve,
        |raw| dm_codegen_byond::decode_constant_string_literal(raw).ok().flatten(),
        |expr| dm_codegen_byond::nameof_reference(expr).map(str::to_owned),
    )
}
