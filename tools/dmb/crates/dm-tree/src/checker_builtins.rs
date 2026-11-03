//! Hash-pinned checker builtin facts in the native semantic owner.
//!
//! Imported from SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc,
//! GPL-3.0, Tad Hardesty and contributors. This catalog is complete ONLY for
//! that checker's fixed builtin DSL. It is NOT a BYOND runtime slot/ABI catalog.
//! Runtime intrinsic queries and source declarations remain untouched.
use super::*;
use dm_ir::{
    DeclarationMeaning, PackedU128, Parameter, ProcedureMetadata, ProcedureSignature,
    ResolveQuery as Q, ResolvedMeaning as M, SemanticValue,
};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    sync::{Arc, OnceLock},
};

pub const REFERENCE_COMMIT: &str = "0290db5c752fa292f9824521515b603a2afd11dc";
pub const BUILTINS_SHA256: &str =
    "927c3979e2e36715c4fd5ee5db87d09a70da1d77805967cf1d58081c67a2a33a";
pub const MACRO_SHA256: &str = "5d7f97effb8282b0ecb97778f690ff5bbf42bb15e735204823e2657dbf9087e9";
pub const PARENTS_SHA256: &str = "14140324324826cf2d165215ebe547d740b3fa7f1b3e84cfd335654aba402f90";
pub const FLAGS_SHA256: &str = "09fa36aab0ce183a2e35da243ff919f6862e2af3e0c4b082d756a6345d303768";
pub const EXPECTED_FACTS_SHA256: &str =
    "e85ec37a11cb04217bf0ed1552bd6378af5417d97e94c9466fcd8aef8626fa2d";
#[derive(Clone, Copy, Debug)]
pub(super) enum RawDefault {
    Number(u32),
    Text(&'static str),
    Type(&'static str),
}
#[derive(Clone, Copy, Debug)]
pub(super) struct RawParameter {
    name: &'static str,
    source_default: Option<&'static str>,
}
#[derive(Clone, Copy, Debug)]
pub(super) struct RawBuiltin {
    ordinal: u32,
    owner: &'static str,
    name: &'static str,
    // Form: type/declare/override/implicit. Kind: type/field/proc/verb.
    form: u8,
    kind: u8,
    type_path: Option<&'static str>,
    flags: Option<u32>,
    reference_flags: Option<u32>,
    default_syntax: Option<&'static str>,
    default: Option<RawDefault>,
    parameters: &'static [RawParameter],
}
#[path = "checker_builtin_data.rs"]
mod data;

/// One native semantic metadata row, preserving fixed-DSL source provenance.
/// No executable body, alternative parser or runtime class/slot is created.
#[derive(Clone, Debug)]
pub struct CheckerBuiltinDeclaration {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub kind: MemberKind,
    pub ordinal: u32,
    pub definition: DefinitionMode,
    pub reference_flags: Option<u32>,
    pub reference_default_syntax: Option<&'static str>,
    pub reference_parameter_defaults: Arc<[Option<&'static str>]>,
    pub metadata: Arc<DeclarationMeaning>,
}
#[derive(Clone, Debug)]
pub struct CheckerBuiltinCatalog {
    pub profile: PackedU128,
    pub declarations: Arc<[CheckerBuiltinDeclaration]>,
    members: BTreeMap<(SymbolId, SymbolId, MemberKind), usize>,
    spellings: BTreeMap<SymbolId, &'static str>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CheckerBuiltinError {
    FactsHash,
    Shape(&'static str),
    UnknownOwner(SymbolId),
    ParentMismatch(SymbolId),
    Symbol(String),
}

fn frame(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(&(value.len() as u64).to_le_bytes());
    out.extend_from_slice(value.as_bytes());
}
fn optional_string(out: &mut Vec<u8>, value: Option<&str>) {
    out.push(u8::from(value.is_some()));
    if let Some(value) = value {
        frame(out, value);
    }
}
fn optional_u32(out: &mut Vec<u8>, value: Option<u32>) {
    out.push(u8::from(value.is_some()));
    if let Some(value) = value {
        out.extend_from_slice(&value.to_le_bytes());
    }
}
fn fact_bytes(parents: &[(&str, Option<&str>)], rows: &[RawBuiltin]) -> Vec<u8> {
    let mut out = b"dq-pinned-checker-builtin-catalog-v1\0".to_vec();
    for value in [
        REFERENCE_COMMIT,
        BUILTINS_SHA256,
        MACRO_SHA256,
        PARENTS_SHA256,
        FLAGS_SHA256,
    ] {
        frame(&mut out, value);
    }
    out.extend_from_slice(&(parents.len() as u64).to_le_bytes());
    for &(owner, parent) in parents {
        frame(&mut out, owner);
        optional_string(&mut out, parent);
    }
    out.extend_from_slice(&(rows.len() as u64).to_le_bytes());
    for row in rows {
        out.extend_from_slice(&row.ordinal.to_le_bytes());
        frame(&mut out, row.owner);
        frame(&mut out, row.name);
        out.extend([row.form, row.kind]);
        optional_string(&mut out, row.type_path);
        optional_u32(&mut out, row.flags);
        optional_u32(&mut out, row.reference_flags);
        optional_string(&mut out, row.default_syntax);
        match row.default {
            None => out.push(0),
            Some(RawDefault::Number(value)) => {
                out.push(1);
                out.extend_from_slice(&value.to_le_bytes());
            }
            Some(RawDefault::Text(value)) => {
                out.push(2);
                frame(&mut out, value);
            }
            Some(RawDefault::Type(value)) => {
                out.push(3);
                frame(&mut out, value);
            }
        }
        out.extend_from_slice(&(row.parameters.len() as u64).to_le_bytes());
        for parameter in row.parameters {
            frame(&mut out, parameter.name);
            optional_string(&mut out, parameter.source_default);
        }
    }
    out
}
fn verified_profile(
    parents: &[(&str, Option<&str>)],
    rows: &[RawBuiltin],
) -> Result<PackedU128, CheckerBuiltinError> {
    let digest = Sha256::digest(fact_bytes(parents, rows));
    let hex = digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    if hex != EXPECTED_FACTS_SHA256 || hex != data::FACTS_SHA256 {
        return Err(CheckerBuiltinError::FactsHash);
    }
    Ok(u128::from_be_bytes(digest[..16].try_into().unwrap()).into())
}
fn default_value(value: RawDefault) -> SemanticValue {
    match value {
        RawDefault::Number(value) => SemanticValue::NumberBits(value),
        RawDefault::Text(value) => SemanticValue::Text(Arc::from(value.as_bytes())),
        RawDefault::Type(value) => SemanticValue::Type(SymbolId::of(value)),
    }
}
fn blank() -> DeclarationMeaning {
    DeclarationMeaning {
        inherited_opaque: None,
        declared_type: None,
        list_element_type: None,
        display_name: None,
        flags: 0,
        procedure: None,
        array: None,
        initializer: None,
        declared_initializer: None,
        resolved_constant: None,
        canonical: Arc::from([]),
    }
}
fn builtin_ancestor<'a>(
    parents: &BTreeMap<SymbolId, Option<SymbolId>>,
    members: &BTreeMap<(SymbolId, SymbolId, MemberKind), usize>,
    decls: &'a [CheckerBuiltinDeclaration],
    mut owner: SymbolId,
    name: SymbolId,
    kind: MemberKind,
) -> Option<&'a CheckerBuiltinDeclaration> {
    loop {
        if let Some(&index) = members.get(&(owner, name, kind)) {
            return decls.get(index);
        }
        owner = parents.get(&owner).copied().flatten()?;
        // Pinned checker ancestry includes global/root declarations. This is
        // checker-only metadata, deliberately distinct from runtime lookup.
    }
}
fn import() -> Result<CheckerBuiltinCatalog, CheckerBuiltinError> {
    let profile = verified_profile(data::PARENTS, data::ROWS)?;
    if data::PARENTS.len() != 28 || data::ROWS.len() != 842 {
        return Err(CheckerBuiltinError::Shape("pinned declaration roster"));
    }
    let parents: BTreeMap<_, _> = data::PARENTS
        .iter()
        .map(|&(p, parent)| (SymbolId::of(p), parent.map(SymbolId::of)))
        .collect();
    let mut declarations = Vec::new();
    let mut members = BTreeMap::new();
    for (index, row) in data::ROWS.iter().enumerate() {
        if row.ordinal as usize != index {
            return Err(CheckerBuiltinError::Shape("declaration ordinal"));
        }
        if row.kind == 0 {
            continue;
        }
        let owner = SymbolId::of(row.owner);
        let name = SymbolId::of(row.name);
        let kind = match row.kind {
            1 => MemberKind::Var,
            2 => MemberKind::Proc,
            3 => MemberKind::Verb,
            _ => return Err(CheckerBuiltinError::Shape("member kind")),
        };
        if members.contains_key(&(owner, name, kind)) {
            return Err(CheckerBuiltinError::Shape("duplicate pinned member"));
        }
        let mut metadata = if row.form == 2 {
            let parent = parents
                .get(&owner)
                .copied()
                .flatten()
                .ok_or(CheckerBuiltinError::Shape("override parent"))?;
            builtin_ancestor(&parents, &members, &declarations, parent, name, kind)
                .ok_or(CheckerBuiltinError::Shape("override lacks builtin base"))?
                .metadata
                .as_ref()
                .clone()
        } else {
            blank()
        };
        if kind == MemberKind::Var {
            if row.form != 2 {
                let path = row
                    .type_path
                    .ok_or(CheckerBuiltinError::Shape("field type presence"))?;
                if !path.is_empty() {
                    let path = format!("/{path}");
                    let projection = dm_syntax::project_declaration_type(&path);
                    metadata.declared_type = Some(SymbolId::of(projection.runtime_path));
                    metadata.list_element_type = projection
                        .list_element_path
                        .map(|p| SymbolId::of(&format!("/{p}")));
                }
                metadata.flags = row
                    .flags
                    .ok_or(CheckerBuiltinError::Shape("field flags presence"))?;
            }
            metadata.resolved_constant = row.default.map(default_value);
        } else {
            let parameters = row
                .parameters
                .iter()
                .map(|p| Parameter {
                    name: SymbolId::of(p.name),
                    declared_type: None,
                    list_element_type: None,
                    flags: 0,
                    array: None,
                    default: None,
                    input_annotation: None,
                    source_expression: None,
                    relative_span: dm_syntax::Span::new(0, 0),
                })
                .collect::<Vec<_>>();
            metadata.procedure = Some(Arc::new(ProcedureMetadata {
                signature: ProcedureSignature {
                    parameters: parameters.into(),
                    variadic: false,
                    return_annotation: None,
                },
                settings: Arc::from([]),
            }));
        }
        // Unevaluated Rust macro syntax is provenance, never reparsed as DM.
        let mut canonical = b"dq-checker-builtin-row-v1\0".to_vec();
        canonical.extend_from_slice(&profile.to_le_bytes());
        canonical.extend_from_slice(&row.ordinal.to_le_bytes());
        optional_string(&mut canonical, row.default_syntax);
        optional_u32(&mut canonical, row.reference_flags);
        metadata.canonical = canonical.into();
        let declaration = CheckerBuiltinDeclaration {
            owner,
            name,
            kind,
            ordinal: row.ordinal,
            definition: match row.form {
                1 => DefinitionMode::Declare,
                2 => DefinitionMode::Override,
                3 => DefinitionMode::Implicit,
                _ => return Err(CheckerBuiltinError::Shape("definition form")),
            },
            reference_flags: row.reference_flags,
            reference_default_syntax: row.default_syntax,
            reference_parameter_defaults: row
                .parameters
                .iter()
                .map(|p| p.source_default)
                .collect::<Vec<_>>()
                .into(),
            metadata: Arc::new(metadata),
        };
        members.insert((owner, name, kind), declarations.len());
        declarations.push(declaration);
    }
    // Fixed catalog spellings borrow generated static bytes. They never clone
    // the source SymbolTable or publish extra source-name presence facts.
    let mut spellings = BTreeMap::new();
    let mut add = |text: &'static str| -> Result<(), CheckerBuiltinError> {
        let symbol = SymbolId::of(text);
        if spellings
            .insert(symbol, text)
            .is_some_and(|old| old != text)
        {
            return Err(CheckerBuiltinError::Symbol(format!(
                "fixed catalog hash collision: {text}"
            )));
        }
        Ok(())
    };
    for &(owner, parent) in data::PARENTS {
        add(owner)?;
        if let Some(parent) = parent {
            add(parent)?;
        }
    }
    for row in data::ROWS {
        add(row.owner)?;
        add(row.name)?;
        for parameter in row.parameters {
            add(parameter.name)?;
        }
        if let Some(RawDefault::Type(path)) = row.default {
            add(path)?;
        }
    }
    Ok(CheckerBuiltinCatalog {
        profile,
        declarations: declarations.into(),
        members,
        spellings,
    })
}
fn pinned_catalog_storage()->&'static Result<Arc<CheckerBuiltinCatalog>,CheckerBuiltinError>{
    static CATALOG: OnceLock<Result<Arc<CheckerBuiltinCatalog>, CheckerBuiltinError>> = OnceLock::new();
    CATALOG.get_or_init(||import().map(Arc::new))
}
pub fn pinned_catalog() -> Result<Arc<CheckerBuiltinCatalog>, CheckerBuiltinError> {pinned_catalog_storage().clone()}
impl CheckerBuiltinCatalog {
    /// Borrow fixed hash-verified spelling bytes only. This DATA projection does
    /// not validate a source tree or grant a builtin/source callable identity.
    pub fn spelling(&self,symbol:SymbolId)->Option<&'static str>{self.spellings.get(&symbol).copied()}
    /// Fixed metadata DATA only; callable identity still requires the exact
    /// immutable tree/profile and original catalog metadata Arc join.
    pub fn own_callable(&self,owner:SymbolId,name:SymbolId,verb:bool)->Option<&CheckerBuiltinDeclaration>{let kind=if verb{MemberKind::Verb}else{MemberKind::Proc};self.members.get(&(owner,name,kind)).and_then(|index|self.declarations.get(*index))}
}
impl SemanticTree {
    /// Validate the fixed profile against this ORIGINAL compiler owner. The
    /// provider is immutable and always available for its exact hash; there is
    /// no absent-to-attached state and no source identity/world mutation.
    pub fn validate_checker_builtin_profile(
        &self,
        profile: PackedU128,
    ) -> Result<(), CheckerBuiltinError> {
        #[cfg(test)]PROFILE_VALIDATIONS.with(|count|count.set(count.get()+1));
        let catalog = pinned_catalog()?;
        if profile != catalog.profile {
            return Err(CheckerBuiltinError::Shape("foreign checker profile"));
        }
        for &(owner, parent) in data::PARENTS {
            let owner = SymbolId::of(owner);
            let id = self
                .lookup_type(owner)
                .ok_or(CheckerBuiltinError::UnknownOwner(owner))?;
            if self.parent(id).map(|id| self.types[id.index()].path) != parent.map(SymbolId::of) {
                return Err(CheckerBuiltinError::ParentMismatch(owner));
            }
        }
        for (&id, &spelling) in &catalog.spellings {
            if self
                .symbols
                .text(id)
                .is_some_and(|source| source != spelling)
            {
                return Err(CheckerBuiltinError::Symbol(format!(
                    "source/catalog hash collision: {spelling}"
                )));
            }
        }
        Ok(())
    }
    pub fn checker_builtin_profile(&self) -> Option<PackedU128> {
        let profile = pinned_catalog().ok()?.profile;
        self.validate_checker_builtin_profile(profile).ok()?;
        Some(profile)
    }
    /// Exact checker/source type presence, independent of runtime ABI member
    /// completeness. Engine-only extra types are NOT checker source types.
    /// `declarations()` is the authored roster: finish_with_engine removes the
    /// seed prefix (adapter.rs), and retained builds preserve that same roster.
    pub fn checker_source_type_presence(
        &self,
        profile: PackedU128,
        path: &str,
    ) -> Result<bool, CheckerBuiltinError> {self.checker_source_type_presence_using(path,||self.validate_checker_builtin_profile(profile))}
    /// Exact Original0290 builtin-only type roster, including types without members.
    /// An authored reopening does not change builtin identity; a runtime ABI or
    /// authored-only type cannot enter the pinned DSL roster.
    pub fn checker_builtin_type_presence_validated(&self,profile:PackedU128,path:&str,proof:&ValidatedCheckerProfile<'_>)->Result<bool,CheckerBuiltinError>{
        proof.require(self,profile)?;
        if self.symbols.text(SymbolId::of(path)).is_some_and(|actual|actual!=path){return Err(CheckerBuiltinError::Symbol("checker builtin type spelling collision".into()))}
        // Original ObjectTree root.path is empty; the native catalog normalizes it to slash.
        Ok(if path.is_empty(){true}else if path=="/"{false}else{data::PARENTS.iter().any(|(builtin,_)|*builtin==path)})
    }
    pub fn checker_source_type_presence_validated(&self,profile:PackedU128,path:&str,proof:&ValidatedCheckerProfile<'_>)->Result<bool,CheckerBuiltinError>{self.checker_source_type_presence_using(path,||proof.require(self,profile))}
    fn checker_source_type_presence_using(&self,path:&str,validate:impl FnOnce()->Result<(),CheckerBuiltinError>)->Result<bool,CheckerBuiltinError>{
        validate()?;
        let symbol = SymbolId::of(path);
        if self
            .symbols
            .text(symbol)
            .is_some_and(|actual| actual != path)
        {
            return Err(CheckerBuiltinError::Symbol(
                "checker source type spelling collision".into(),
            ));
        }
        if data::PARENTS.iter().any(|(builtin, _)| *builtin == path) {
            return Ok(true);
        }
        if !path.starts_with('/') || path.len() == 1 {
            return Ok(false);
        }
        for target in self.declarations() {
            let owner = match target {
                crate::Target::Type(id) => self.type_node(*id),
                crate::Target::Member(id) => self.member(*id).and_then(|m| self.type_node(m.owner)),
            }
            .ok_or(CheckerBuiltinError::Shape(
                "authored type target is unavailable",
            ))?;
            let name = self
                .symbols
                .text(owner.path)
                .ok_or(CheckerBuiltinError::Shape(
                    "authored type spelling is unavailable",
                ))?;
            if name == path
                || name
                    .strip_prefix(path)
                    .is_some_and(|tail| tail.starts_with('/'))
            {
                return Ok(true);
            }
        }
        Ok(false)
    }
    /// Fixed spelling projection. No source symbol is interned or copied.
    pub fn checker_builtin_spelling(
        &self,
        profile: PackedU128,
        symbol: SymbolId,
    ) -> Option<&'static str> {
        self.validate_checker_builtin_profile(profile).ok()?;
        pinned_catalog().ok()?.spellings.get(&symbol).copied()
    }
    pub(crate) fn resolve_checker_builtin(
        &self,
        query: Q,
        profile: PackedU128,
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
        presence: bool,
    ) -> M {self.resolve_checker_builtin_using(query,profile,owner,name,kind,presence,||self.validate_checker_builtin_profile(profile),None).expect("ordinary native builtin declaration encoding failed")}
    pub(crate) fn resolve_checker_builtin_admitted(&self,query:Q,profile:PackedU128,owner:SymbolId,name:SymbolId,kind:MemberKind,presence:bool,work:&mut dyn dm_ir::CanonicalWork)->std::io::Result<M>{
        self.resolve_checker_builtin_using(query,profile,owner,name,kind,presence,||self.validate_checker_builtin_profile(profile),Some(work))
    }
    fn resolve_checker_builtin_using(
        &self,
        query: Q,
        profile: PackedU128,
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
        presence: bool,
        validate:impl FnOnce()->Result<(),CheckerBuiltinError>,
        mut work:Option<&mut dyn dm_ir::CanonicalWork>,
    ) -> std::io::Result<M> {
        if validate().is_err() {
            return Ok(M::Unsupported(query));
        }
        let Ok(catalog) = pinned_catalog() else {
            return Ok(M::Unsupported(query));
        };
        let Some(mut current) = self.lookup_type(owner) else {
            return Ok(M::Unsupported(query));
        };
        loop {
            if let Some(work)=&mut work{work.poll()?;}
            let declaring_owner = self.types[current.index()].path;
            if let Some(&index) = catalog.members.get(&(declaring_owner, name, kind)) {
                if presence {
                    return Ok(M::Presence(true));
                }
                let data = Arc::clone(&catalog.declarations[index].metadata);
                let bytes=match &mut work{Some(work)=>data.canonical_bytes_using(*work)?,None=>data.canonical_bytes()};
                let mut fingerprint=xxhash_rust::xxh3::Xxh3::new();fingerprint.update(&bytes);fingerprint.update(&profile.to_le_bytes());
                return Ok(M::Member {
                    owner: declaring_owner,
                    name,
                    data,
                    fingerprint: fingerprint.digest128().into(),
                });
            }
            let Some(parent) = self.parent(current) else {
                break;
            };
            // Pinned TypeRef::get_proc/get_var_declaration walks root too.
            // Runtime IntrinsicCallable keeps its separate namespace contract.
            current = parent;
        }
        Ok(if presence { M::Presence(false) } else { M::Missing })
    }
}
#[cfg(test)]
#[path = "checker_builtin_tests.rs"]
mod tests;

/// Scalar identity in the ORIGINAL hash-certified fixed DSL. This proves
/// checker declaration provenance, not a runtime effect/purity contract.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct CheckerBuiltinProcedureIdentity {
    profile: PackedU128,
    ordinal: u32,
}
impl CheckerBuiltinProcedureIdentity {
    pub fn profile(self) -> PackedU128 {
        self.profile
    }
    pub fn ordinal(self) -> u32 {
        self.ordinal
    }
}
impl SemanticTree {
    pub fn checker_builtin_procedure_identity(
        &self,
        profile: PackedU128,
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
        metadata: &Arc<DeclarationMeaning>,
    ) -> Result<CheckerBuiltinProcedureIdentity, CheckerBuiltinError> {
        self.validate_checker_builtin_profile(profile)?;
        let catalog = pinned_catalog()?;
        let kind = if verb {
            MemberKind::Verb
        } else {
            MemberKind::Proc
        };
        let index = *catalog
            .members
            .get(&(owner, name, kind))
            .ok_or(CheckerBuiltinError::Shape("builtin procedure absent"))?;
        let row = &catalog.declarations[index];
        if !Arc::ptr_eq(&row.metadata, metadata)
            || row.metadata.procedure.is_none()
            || row.metadata.inherited_opaque.is_some()
        {
            return Err(CheckerBuiltinError::Shape(
                "builtin procedure is not original catalog metadata",
            ));
        }
        Ok(CheckerBuiltinProcedureIdentity {
            profile,
            ordinal: row.ordinal,
        })
    }
    /// Borrow the original declaration; no projected builtin table or AST.
    pub fn with_checker_builtin_procedure<R>(
        &self,
        identity: CheckerBuiltinProcedureIdentity,
        read: impl FnOnce(&CheckerBuiltinDeclaration) -> R,
    ) -> Result<R, CheckerBuiltinError> {
        self.validate_checker_builtin_profile(identity.profile)?;
        let catalog = pinned_catalog()?;
        let row = catalog
            .declarations
            .iter()
            .find(|row| row.ordinal == identity.ordinal)
            .ok_or(CheckerBuiltinError::Shape("builtin ordinal absent"))?;
        if !matches!(row.kind, MemberKind::Proc | MemberKind::Verb)
            || row.metadata.procedure.is_none()
        {
            return Err(CheckerBuiltinError::Shape(
                "builtin identity is not a callable",
            ));
        }
        if catalog
            .members
            .get(&(row.owner, row.name, row.kind))
            .map(|i| catalog.declarations[*i].ordinal)
            != Some(identity.ordinal)
        {
            return Err(CheckerBuiltinError::Shape(
                "builtin identity is not selected declaration",
            ));
        }
        Ok(read(row))
    }
}

#[path="checker_profile.rs"]mod profile;
pub use profile::ValidatedCheckerProfile;
#[cfg(test)]thread_local!{static PROFILE_VALIDATIONS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}

#[cfg(test)]mod catalog_spelling_tests{use super::*;#[test]fn fixed_catalog_spelling_covers_every_actual_callable_and_parameter_without_source_interning(){let catalog=pinned_catalog().unwrap();let mut callables=0;let mut parameters=0;for row in catalog.declarations.iter().filter(|row|matches!(row.kind,MemberKind::Proc|MemberKind::Verb)){callables+=1;for symbol in[row.owner,row.name]{let text=catalog.spelling(symbol).expect("issued builtin spelling");assert_eq!(SymbolId::of(text),symbol);}for parameter in row.metadata.procedure.as_ref().unwrap().signature.parameters.iter(){parameters+=1;let text=catalog.spelling(parameter.name).expect("issued parameter spelling");assert_eq!(SymbolId::of(text),parameter.name);}}assert!(callables>100);assert!(parameters>100);assert!(catalog.spelling(SymbolId::of("__not_a_pinned_catalog_symbol__")).is_none());}}

/// Original analysis declaration seed, issued only from the hash-verified fixed
/// checker catalog. Runtime members remain explicitly incomplete; this owner
/// cannot certify executable slots, ABI, or absence of a runtime intrinsic.
#[derive(Debug)]
pub struct OriginalAnalysisSeed { seed: crate::frontend::EngineSeed, profile: PackedU128 }
impl OriginalAnalysisSeed {
    pub fn frontend_seed(&self)->&crate::frontend::EngineSeed { &self.seed }
    pub fn profile(&self)->PackedU128 { self.profile }
}
pub fn original_analysis_seed()->Result<Arc<OriginalAnalysisSeed>,CheckerBuiltinError>{
    static SEED:OnceLock<Result<Arc<OriginalAnalysisSeed>,CheckerBuiltinError>>=OnceLock::new();
    SEED.get_or_init(||{
        let catalog=pinned_catalog()?;
        let mut symbols=dm_ir::SymbolTable::default();
        let mut parents=Vec::with_capacity(data::PARENTS.len());
        for &(path,parent) in data::PARENTS {
            symbols.intern(path).map_err(|error|CheckerBuiltinError::Symbol(format!("{error:?}")))?;
            parents.push((SymbolId::of(path),parent.map(SymbolId::of)));
        }
        let mut hash=Sha256::new();hash.update(b"original-analysis-declaration-seed-v1");
        hash.update(EXPECTED_FACTS_SHA256.as_bytes());hash.update(PARENTS_SHA256.as_bytes());
        let digest=hash.finalize();let identity=u128::from_le_bytes(digest[..16].try_into().unwrap());
        Ok(Arc::new(OriginalAnalysisSeed{
            profile:catalog.profile,
            seed:crate::frontend::EngineSeed{identity,symbols,
                hierarchy:crate::EngineHierarchy{schema:identity,parents},
                intrinsics:Arc::from([]),fields:Arc::from([])},
        }))
    }).clone()
}

/// Private declaration-only loan from the actual Original seed and pinned catalog.
/// No runtime field, slot, ABI member, source occurrence or alternative index.
#[derive(Clone,Copy)]
pub(crate) struct OriginalVariableDeclarations{catalog:&'static CheckerBuiltinCatalog}
impl OriginalVariableDeclarations{
 pub(crate) fn for_seed(seed:Option<&crate::frontend::EngineSeed>)->Option<Self>{
  let seed=seed?;let original=original_analysis_seed().ok()?;if !std::ptr::eq(seed,original.frontend_seed()){return None}let catalog=pinned_catalog_storage().as_ref().ok()?.as_ref();if catalog.profile!=original.profile(){return None}Some(Self{catalog})
 }
 pub(crate) fn variable(&self,tree:&SemanticTree,owner:SymbolId,name:SymbolId)->Option<&Arc<DeclarationMeaning>>{if self.catalog.spelling(owner)!=tree.symbols().text(owner)||self.catalog.spelling(name)!=tree.symbols().text(name){return None}let index=*self.catalog.members.get(&(owner,name,MemberKind::Var))?;let row=&self.catalog.declarations[index];(row.metadata.procedure.is_none()&&row.metadata.inherited_opaque.is_none()).then_some(&row.metadata)}
}
