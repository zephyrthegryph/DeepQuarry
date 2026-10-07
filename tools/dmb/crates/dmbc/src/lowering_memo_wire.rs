//! Versioned disk payload for supported symbolic procedure results.
//! Private modified-descriptor issuers and helper expressions are deliberately
//! not rehydrated through an unchecked serde derive: those units miss on disk.
use crate::lowering::{LoweredUnit, Namespace, UnitIdentity};
use crate::lowering_memo::ResolverRead;
use dm_codegen_byond::lower_resolver::{ResolvedInstance, ResolvedSlot, ResolverProc};
use dm_codegen_byond::procedure_abi::{ArgumentSource, Category, ProcLayout};
use dm_ir::{ProcedureIdentity, ProcedureStaticIdentity, ResolveQuery, Resolver, SymbolId};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::Arc};

#[derive(Serialize,Deserialize)]
struct Abi {
    display:Option<Vec<u8>>, description:Option<Vec<u8>>, category:u8, category_text:Vec<u8>,
    source_kind:u8, source_parameter:u8, flags:u32, invisibility:Option<u8>,
    arguments:Vec<(u8,u8)>,
}
#[derive(Serialize,Deserialize)]
struct Payload {
    version:u32, key:Vec<u8>, identity:ProcedureIdentity, effective:bool,
    reads:Vec<(ResolveQuery,Vec<u8>)>,
    code:dm_codegen_byond::SimpleProc,
    slots:Vec<(dm_codegen_byond::Symbol,SymbolId,SymbolId,SymbolId)>,
    resources:BTreeMap<String,u128>,
    instances:Vec<(String,SymbolId,SymbolId)>,
    procedure_values:BTreeMap<dm_codegen_byond::Symbol,ProcedureIdentity>,
    procedure_statics:BTreeMap<dm_codegen_byond::Symbol,ProcedureStaticIdentity>,
    debug:Vec<(String,u32)>, abi:Option<Abi>,
}
pub(crate) fn encode(key:&[u8],reads:&[ResolverRead],unit:&LoweredUnit)->Option<Vec<u8>> {
    if !unit.code.modified_instances.is_empty() || !unit.source_helpers.is_empty() {return None;}
    let abi=match unit.abi.as_ref() {
        None=>None,
        Some(abi)=>{
            if !abi.source_helpers.is_empty() {return None;}
            let arguments=abi.argument_sources.iter().map(|source|match source {
                ArgumentSource::Builtin{kind,parameter}=>Some((*kind,*parameter)),
                ArgumentSource::Helper{..}=>None,
            }).collect::<Option<Vec<_>>>()?;
            let (category,category_text)=match &abi.layout.category {
                Category::Default=>(0,Vec::new()),Category::Null=>(1,Vec::new()),
                Category::Text(bytes)=>(2,bytes.clone()),
            };
            Some(Abi { display:abi.layout.display_name.clone(),description:abi.layout.description.clone(),
                category,category_text,source_kind:abi.layout.source_kind,source_parameter:abi.layout.source_parameter,
                flags:abi.layout.flags,invisibility:abi.layout.invisibility,arguments })
        }
    };
    let payload=Payload {version:1,key:key.to_vec(),
        identity:ProcedureIdentity {owner:unit.identity.owner,name:unit.identity.name,
            verb:unit.identity.namespace==Namespace::Verb,occurrence:unit.identity.occurrence},
        effective:unit.effective,reads:reads.iter().map(|read|(read.query,read.answer.canonical_bytes())).collect(),
        code:unit.code.procedure.clone(),
        slots:unit.code.slots.iter().map(|(key,slot)|(key.clone(),slot.symbol,slot.owner,slot.name)).collect(),
        resources:unit.code.resources.clone(),instances:unit.code.instances.iter().map(|(key,value)|
            (key.clone(),value.alias,value.runtime_type)).collect(),
        procedure_values:unit.code.procedure_values.clone(),procedure_statics:unit.code.procedure_statics.clone(),
        debug:unit.debug_origins.entries.iter().map(|origin|(origin.semantic_path.clone(),origin.line)).collect(),abi};
    serde_json::to_vec(&payload).ok()
}
pub(crate) fn validate(bytes:&[u8])->Result<(),String> {
    let payload:Payload=serde_json::from_slice(bytes).map_err(|error|error.to_string())?;
    if payload.version!=1 {return Err("unsupported lowering payload version".into());}
    if payload.abi.as_ref().is_some_and(|abi|abi.category>2) {return Err("invalid ABI category".into());}
    Ok(())
}
pub(crate) fn decode<R:Resolver>(bytes:&[u8],key:&[u8],frontend:&dm_tree::frontend::ColdFrontend,
    body:&dm_tree::frontend::BodyOccurrence,host:&R)->Option<LoweredUnit> {
    validate(bytes).ok()?;
    let payload:Payload=serde_json::from_slice(bytes).ok()?;
    if payload.key!=key || !payload.reads.iter().all(|(query,answer)|host.resolve(*query).canonical_bytes()==*answer) {return None;}
    let tree=&frontend.snapshot.tree;
    let member=tree.member(body.member)?;
    let owner=tree.type_node(member.owner)?.path;
    if payload.identity.owner!=owner || payload.identity.name!=member.name
        || payload.identity.verb!=(member.kind==dm_tree::MemberKind::Verb) {return None;}
    let abi=payload.abi.map(|abi|Arc::new(crate::procedure_policy::PreparedAbi {
        layout:ProcLayout {display_name:abi.display,description:abi.description,
            category:match abi.category {0=>Category::Default,1=>Category::Null,_=>Category::Text(abi.category_text)},
            source_kind:abi.source_kind,source_parameter:abi.source_parameter,flags:abi.flags,invisibility:abi.invisibility},
        argument_sources:abi.arguments.into_iter().map(|(kind,parameter)|ArgumentSource::Builtin{kind,parameter}).collect(),
        source_helpers:Vec::new(),
    }));
    let mut slots=BTreeMap::new();
    for (key,symbol,owner,name) in payload.slots {
        if slots.insert(key,ResolvedSlot {symbol,owner,name}).is_some() {return None;}
    }
    let mut instances=BTreeMap::new();
    for (key,alias,runtime_type) in payload.instances {
        if instances.insert(key,ResolvedInstance {alias,runtime_type}).is_some() {return None;}
    }
    Some(LoweredUnit {identity:UnitIdentity {owner:payload.identity.owner,name:payload.identity.name,
        namespace:if payload.identity.verb {Namespace::Verb}else{Namespace::Proc},occurrence:payload.identity.occurrence},
        effective:tree.resolve(member.owner,member.name,member.kind)==Some(body.member),origin:body.clone(),metadata:Arc::clone(member.metadata.procedure.as_ref()?),abi,
        code:ResolverProc {modified_instances:BTreeMap::new(),procedure_values:payload.procedure_values,
            procedure_statics:payload.procedure_statics,procedure:payload.code,slots,resources:payload.resources,instances},
        debug_origins:crate::debug_sources::DebugOrigins {entries:payload.debug.into_iter().map(|(semantic_path,line)|
            crate::debug_sources::DebugOrigin{semantic_path,line}).collect()},source_helpers:Vec::new() })
}

