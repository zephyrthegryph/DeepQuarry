//! Answers come from the compiler's Resolver contract, including negatives.
use super::{constant, emit, expression, ExportError};
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver, SymbolId, SymbolTable};
use dm_tree::{MemberKind, SemanticTree};
use serde_json::{json, Value};
use std::io::Write;

pub struct AnalysisQuery<'a> {
    pub subject: Option<&'a str>,
    pub query: ResolveQuery,
}
fn symbol(symbols: &SymbolTable, id: SymbolId) -> Value {
    json!({"id":format!("{:016x}",id.bits()),"text":symbols.text(id)})
}
fn answer(symbols: &SymbolTable, meaning: &ResolvedMeaning) -> Result<Value, ExportError> {
    use ResolvedMeaning as M;
    Ok(match meaning {
        M::Unsupported(_) => json!({"status":"unsupported"}),
        M::Missing => json!({"status":"missing"}),
        M::Presence(value) => json!({"status":"known","kind":"presence","value":value}),
        M::DeclaredType(value) => {
            json!({"status":"known","kind":"declared_type","value":value.map(|id|symbol(symbols,id))})
        }
        M::InstanceField {
            declaring_owner,
            name,
        } => {
            json!({"status":"known","kind":"instance_field","owner":symbol(symbols,*declaring_owner),"name":symbol(symbols,*name)})
        }
        M::Slot {
            symbol: slot,
            owner,
            name,
        } => {
            json!({"status":"known","kind":"shared_slot","slot":symbol(symbols,*slot),"owner":symbol(symbols,*owner),"name":symbol(symbols,*name)})
        }
        M::Symbol(id) => json!({"status":"known","kind":"symbol","value":symbol(symbols,*id)}),
        M::Symbols(ids) => {
            json!({"status":"known","kind":"symbols","values":ids.iter().map(|id|symbol(symbols,*id)).collect::<Vec<_>>()})
        }
        M::Value(value) => {
            json!({"status":"known","kind":"value","value":constant(value,symbols)?})
        }
        M::Members(values) => {
            json!({"status":"known","kind":"members","values":values.iter().map(|value|answer(symbols,value)).collect::<Result<Vec<_>,_>>()?})
        }
        M::Member {
            owner,
            name,
            fingerprint,
            data,
        } => {
            let opaque = data.inherited_opaque.as_ref();
            let (declared_type, type_status) = match opaque.map(|base| base.declared_type) {
                Some(dm_ir::DeclaredTypeKnowledge::Known(path)) => (Some(path), "known"),
                Some(dm_ir::DeclaredTypeKnowledge::KnownUntyped) => (None, "known_untyped"),
                Some(dm_ir::DeclaredTypeKnowledge::Unsupported) => (None, "unsupported"),
                None => (
                    data.declared_type,
                    if data.declared_type.is_some() {
                        "known"
                    } else {
                        "known_untyped"
                    },
                ),
            };
            json!({"status":"known","kind":"member","owner":symbol(symbols,*owner),"name":symbol(symbols,*name),"fingerprint":format!("{fingerprint:032x}"),
                "flags":opaque.is_none().then_some(data.flags),"flags_status":if opaque.is_some() {"unknown"} else {"known"},
                "declared_type":declared_type.map(|path|symbol(symbols,path)),"declared_type_status":type_status,
                "list_element_type":opaque.is_none().then_some(data.list_element_type).flatten().map(|path|symbol(symbols,path)),
                "list_element_type_status":if opaque.is_some() {"unknown"} else {"known"},
                "initializer":expression(data.initializer.as_ref(),symbols)?,"opaque":opaque.is_some()})
        }
        M::Resource { path, content } => {
            json!({"status":"known","kind":"resource","path":symbol(symbols,*path),"content":format!("{content:032x}")})
        }
        M::IntrinsicProc {
            declaring_owner,
            name,
        } => {
            json!({"status":"known","kind":"intrinsic_proc","owner":symbol(symbols,*declaring_owner),"name":symbol(symbols,*name),"abi_status":"unsupported"})
        }
        M::RetainedProc {
            declaring_owner,
            name,
            verb,
            engine_identity,
            wire_proc,
        } => {
            json!({"status":"known","kind":"retained_proc","owner":symbol(symbols,*declaring_owner),"name":symbol(symbols,*name),"verb":verb,"engine_identity":format!("{engine_identity:032x}"),"wire_proc":wire_proc})
        }
        M::ProcedureStatic(value) => {
            json!({"status":"known","kind":"procedure_static","owner":symbol(symbols,value.identity.procedure.owner),"procedure":symbol(symbols,value.identity.procedure.name),"verb":value.identity.procedure.verb,"occurrence":value.identity.procedure.occurrence,"name":symbol(symbols,value.identity.name),"flags":value.modifiers,"declared_type":value.declared_type.map(|id|symbol(symbols,id))})
        }
    })
}
/// Stream caller-selected queries against the same immutable resolver used by
/// compilation. The query wire is a JSON string to preserve every integer bit
/// (including u128 resource context) across consumers with 53-bit numbers.
pub fn write_queries_jsonl<'a>(
    symbols: &SymbolTable,
    resolver: &(impl Resolver + ?Sized),
    queries: impl IntoIterator<Item = AnalysisQuery<'a>>,
    writer: &mut impl Write,
) -> Result<usize, ExportError> {
    let mut count = 0;
    for query in queries {
        let meaning = resolver.resolve(query.query);
        let domain = match query.query.domain() {
            ReadDomain::Tree => "tree",
            ReadDomain::ResourceSearch => "resource_search",
        };
        emit(
            writer,
            json!({"row":"resolved_query","schema":"dm-resolved-query-v1","subject":query.subject,
            "query_wire":serde_json::to_string(&query.query).map_err(ExportError::Json)?,
            "domain":domain,"domain_version":resolver.domain_version(query.query.domain()).map(|version|format!("{version:032x}")),
            "meaning_fingerprint":format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&meaning.canonical_bytes())),
            "answer":answer(symbols,&meaning)?}),
        )?;
        count += 1;
    }
    Ok(count)
}
pub(super) fn write_member_queries(
    tree: &SemanticTree,
    keys: &[String],
    writer: &mut impl Write,
) -> Result<usize, ExportError> {
    let mut count = 0;
    for (member, key) in tree.members().iter().zip(keys) {
        let owner = tree
            .type_node(member.owner)
            .ok_or(ExportError::InvalidModel("unknown member owner"))?
            .path;
        let name = member.name;
        let queries = match member.kind {
            MemberKind::Var => vec![
                ResolveQuery::VarStorage { owner, name },
                ResolveQuery::DeclaredVarType { owner, name },
                ResolveQuery::Constant { owner, name },
            ],
            MemberKind::Proc | MemberKind::Verb => vec![
                ResolveQuery::Proc {
                    owner,
                    name,
                    verb: member.kind == MemberKind::Verb,
                },
                ResolveQuery::MethodProcedureValue {
                    owner,
                    name,
                    verb: member.kind == MemberKind::Verb,
                },
            ],
        };
        count += write_queries_jsonl(
            tree.symbols(),
            tree,
            queries.into_iter().map(|query| AnalysisQuery {
                subject: Some(key),
                query,
            }),
            writer,
        )?;
    }
    Ok(count)
}
#[cfg(test)]
#[path = "query_export_tests.rs"]
mod tests;
