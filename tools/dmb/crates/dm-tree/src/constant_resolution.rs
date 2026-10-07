//! Demand-driven scalar evaluation over one immutable declaration snapshot.
//! Backend decoding is explicit; unsupported values never become null/missing.
use crate::constants::{evaluate_with, Constant};
use crate::{DefinitionMode, MemberId, MemberKind, SemanticTree, TreeSnapshot};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SemanticValue, SymbolId};
use dm_syntax::Expr;
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum ScalarQuery {
    Const { owner: SymbolId, name: SymbolId },
    DeclaredDefault { owner: SymbolId, name: SymbolId },
    EffectiveDefault { owner: SymbolId, name: SymbolId },
}
impl ScalarQuery {
    fn parts(self) -> (u8, SymbolId, SymbolId) {
        match self {
            Self::Const { owner, name } => (0, owner, name),
            Self::DeclaredDefault { owner, name } => (1, owner, name),
            Self::EffectiveDefault { owner, name } => (2, owner, name),
        }
    }
    fn encode(self, bytes: &mut Vec<u8>) {
        let (domain, owner, name) = self.parts();
        bytes.push(domain);
        bytes.extend_from_slice(&owner.bits().to_le_bytes());
        bytes.extend_from_slice(&name.bits().to_le_bytes());
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UnsupportedReason {
    MissingDeclaration,
    NotConst,
    OpaqueInheritedMetadata,
    MissingInitializer,
    RuntimeOrUnsupportedExpression,
    BackendInterpretation,
    UnknownType,
}
impl UnsupportedReason {
    fn tag(self) -> u8 {
        match self {
            Self::MissingDeclaration => 0,
            Self::NotConst => 1,
            Self::OpaqueInheritedMetadata => 2,
            Self::MissingInitializer => 3,
            Self::RuntimeOrUnsupportedExpression => 4,
            Self::BackendInterpretation => 5,
            Self::UnknownType => 6,
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ScalarOutcome {
    Value(SemanticValue),
    Unsupported(UnsupportedReason),
    /// Actual dependency-cycle traversal, rotated to its lowest structural key.
    Cycle(Arc<[ScalarQuery]>),
}

pub struct ScalarBackend<'a> {
    /// Caller-pinned decoder/nameof policy identity, mandatory for cache identity.
    pub identity: u128,
    pub decode_string: &'a dyn Fn(&str) -> Option<Vec<u8>>,
    pub nameof: &'a dyn Fn(&Expr) -> Option<String>,
}

#[derive(Clone, Debug)]
pub struct ScalarSnapshot {
    pub source: TreeSnapshot,
    pub identity: u128,
    pub backend_identity: u128,
    pub requested: Arc<[ScalarQuery]>,
    pub outcomes: Arc<BTreeMap<ScalarQuery, ScalarOutcome>>,
    pub dependencies: Arc<BTreeMap<ScalarQuery, Arc<[ScalarQuery]>>>,
}
impl ScalarSnapshot {
    pub fn outcome(&self, query: ScalarQuery) -> Option<&ScalarOutcome> {
        self.outcomes.get(&query)
    }
}

#[derive(Default)]
struct Memo {
    values: BTreeMap<ScalarQuery, ScalarOutcome>,
    active: Vec<ScalarQuery>,
    edges: BTreeMap<ScalarQuery, BTreeSet<ScalarQuery>>,
}
struct Pass<'a> {
    tree: &'a SemanticTree,
    backend: &'a ScalarBackend<'a>,
    memo: RefCell<Memo>,
}
impl Pass<'_> {
    fn member(&self, owner: SymbolId, name: SymbolId) -> Option<MemberId> {
        self.tree
            .lookup_type(owner)
            .and_then(|owner| self.tree.resolve(owner, name, MemberKind::Var))
    }
    fn query(&self, query: ScalarQuery) -> ScalarOutcome {
        {
            let memo = self.memo.borrow();
            if let Some(value) = memo.values.get(&query) {
                return value.clone();
            }
            if let Some(index) = memo.active.iter().position(|active| *active == query) {
                let mut cycle = memo.active[index..].to_vec();
                let first = cycle
                    .iter()
                    .enumerate()
                    .min_by_key(|(_, key)| **key)
                    .map_or(0, |(index, _)| index);
                cycle.rotate_left(first);
                return ScalarOutcome::Cycle(cycle.into());
            }
        }
        self.memo.borrow_mut().active.push(query);
        let value = self.evaluate(query);
        let mut memo = self.memo.borrow_mut();
        memo.active.pop();
        memo.values.insert(query, value.clone());
        value
    }
    fn evaluate(&self, query: ScalarQuery) -> ScalarOutcome {
        let (_, owner, name) = query.parts();
        let Some(id) = self.member(owner, name) else {
            return ScalarOutcome::Unsupported(UnsupportedReason::MissingDeclaration);
        };
        let node = self
            .tree
            .member(id)
            .expect("resolved member belongs to tree");
        let metadata = &node.metadata;
        if metadata.inherited_opaque.is_some()
            && !matches!(query, ScalarQuery::EffectiveDefault { .. })
        {
            return ScalarOutcome::Unsupported(UnsupportedReason::OpaqueInheritedMetadata);
        }
        if matches!(query, ScalarQuery::Const { .. }) && metadata.flags & 2 == 0 {
            return ScalarOutcome::Unsupported(UnsupportedReason::NotConst);
        }
        let (expression, scope) = match query {
            ScalarQuery::DeclaredDefault { .. } => {
                let declaration = self.tree.override_chain(id).into_iter().rev().find(|id| {
                    self.tree
                        .member(*id)
                        .is_some_and(|node| node.definition == DefinitionMode::Declare)
                });
                let owner = declaration
                    .and_then(|id| self.tree.member(id))
                    .map_or(node.owner, |node| node.owner);
                (metadata.declared_initializer.as_ref(), owner)
            }
            _ => (metadata.initializer.as_ref(), node.owner),
        };
        let Some(expression) = expression else {
            return ScalarOutcome::Unsupported(UnsupportedReason::MissingInitializer);
        };
        let Some(text) = expression.source_text(self.tree.symbols()) else {
            return ScalarOutcome::Unsupported(UnsupportedReason::RuntimeOrUnsupportedExpression);
        };
        let failure = RefCell::new(None);
        let result = evaluate_with(
            &text,
            |name| {
                let dependency = if let Some((path, name)) = name.rsplit_once("::") {
                    ScalarQuery::Const {
                        owner: SymbolId::of(path),
                        name: SymbolId::of(name),
                    }
                } else {
                    let owner = self.tree.type_node(scope)?.path;
                    let name = SymbolId::of(name);
                    let owner = if self.member(owner, name).is_some() {
                        owner
                    } else {
                        SymbolId::of("/")
                    };
                    ScalarQuery::Const { owner, name }
                };
                self.memo
                    .borrow_mut()
                    .edges
                    .entry(query)
                    .or_default()
                    .insert(dependency);
                match self.query(dependency) {
                    ScalarOutcome::Value(value) => to_constant(&value, self.tree),
                    unsupported => {
                        if failure.borrow().is_none() {
                            *failure.borrow_mut() = Some(unsupported);
                        }
                        None
                    }
                }
            },
            |raw| {
                let result = (self.backend.decode_string)(raw);
                if result.is_none() && failure.borrow().is_none() {
                    *failure.borrow_mut() = Some(ScalarOutcome::Unsupported(
                        UnsupportedReason::BackendInterpretation,
                    ));
                }
                result
            },
            |expression| {
                let result = (self.backend.nameof)(expression);
                if result.is_none() && failure.borrow().is_none() {
                    *failure.borrow_mut() = Some(ScalarOutcome::Unsupported(
                        UnsupportedReason::BackendInterpretation,
                    ));
                }
                result
            },
        );
        match result {
            Some(value) => to_semantic(value, self.tree).map_or(
                ScalarOutcome::Unsupported(UnsupportedReason::UnknownType),
                ScalarOutcome::Value,
            ),
            None => failure.into_inner().unwrap_or(ScalarOutcome::Unsupported(
                UnsupportedReason::RuntimeOrUnsupportedExpression,
            )),
        }
    }
}

fn to_constant(value: &SemanticValue, tree: &SemanticTree) -> Option<Constant> {
    Some(match value {
        SemanticValue::Null => Constant::Null,
        SemanticValue::NumberBits(bits) => Constant::Number(f32::from_bits(*bits)),
        SemanticValue::Text(bytes) => match String::from_utf8(bytes.to_vec()) {
            Ok(text) => Constant::Text(text),
            Err(error) => Constant::EncodedText(error.into_bytes()),
        },
        SemanticValue::Type(path) => Constant::TypePath(tree.symbols().text(*path)?.into()),
        SemanticValue::Resource(_) | SemanticValue::List(_) => return None,
    })
}
fn to_semantic(value: Constant, tree: &SemanticTree) -> Option<SemanticValue> {
    Some(match value {
        Constant::Null => SemanticValue::Null,
        Constant::Number(value) => SemanticValue::NumberBits(value.to_bits()),
        Constant::Text(text) => SemanticValue::Text(Arc::from(text.as_bytes())),
        Constant::EncodedText(bytes) => SemanticValue::Text(bytes.into()),
        Constant::TypePath(path) => {
            let symbol = SymbolId::of(&path);
            tree.lookup_type(symbol)?;
            if tree.symbols().text(symbol) != Some(path.as_str()) {
                return None;
            }
            SemanticValue::Type(symbol)
        }
    })
}

/// Only selected declarations and transitively reached consts are evaluated.
/// Unsupported/cyclic outcomes are data, not user syntax diagnostics.
pub fn resolve(
    snapshot: &TreeSnapshot,
    requests: &[ScalarQuery],
    backend: &ScalarBackend<'_>,
) -> ScalarSnapshot {
    let requested = requests.iter().copied().collect::<BTreeSet<_>>();
    let pass = Pass {
        tree: &snapshot.tree,
        backend,
        memo: RefCell::new(Memo::default()),
    };
    for query in &requested {
        pass.query(*query);
    }
    let memo = pass.memo.into_inner();
    let dependencies: BTreeMap<_, Arc<[ScalarQuery]>> = memo
        .edges
        .into_iter()
        .map(|(query, edges)| (query, edges.into_iter().collect::<Vec<_>>().into()))
        .collect();
    let mut bytes = b"dm-scalar-overlay-v1\0".to_vec();
    bytes.extend_from_slice(&snapshot.tree.identity().to_le_bytes());
    bytes.extend_from_slice(&backend.identity.to_le_bytes());
    bytes.extend_from_slice(&(requested.len() as u64).to_le_bytes());
    for query in &requested {
        query.encode(&mut bytes);
    }
    for (query, outcome) in &memo.values {
        query.encode(&mut bytes);
        match outcome {
            ScalarOutcome::Value(value) => {
                bytes.push(0);
                let value = value.canonical_bytes();
                bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
                bytes.extend_from_slice(&value);
            }
            ScalarOutcome::Unsupported(reason) => {
                bytes.push(1);
                bytes.push(reason.tag());
            }
            ScalarOutcome::Cycle(cycle) => {
                bytes.push(2);
                bytes.extend_from_slice(&(cycle.len() as u64).to_le_bytes());
                for query in cycle.iter() {
                    query.encode(&mut bytes);
                }
            }
        }
        let edges = dependencies
            .get(query)
            .map_or(&[][..], |edges| edges.as_ref());
        bytes.extend_from_slice(&(edges.len() as u64).to_le_bytes());
        for dependency in edges {
            dependency.encode(&mut bytes);
        }
    }
    ScalarSnapshot {
        source: snapshot.clone(),
        identity: xxhash_rust::xxh3::xxh3_128(&bytes),
        backend_identity: backend.identity,
        requested: requested.into_iter().collect::<Vec<_>>().into(),
        outcomes: Arc::new(memo.values),
        dependencies: Arc::new(dependencies),
    }
}

impl Resolver for ScalarSnapshot {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let (owner, name, constant_query) = match query {
            ResolveQuery::Constant { owner, name } => (owner, name, true),
            ResolveQuery::Var { owner, name } => (owner, name, false),
            ResolveQuery::GlobalVar(name) => (SymbolId::of("/"), name, false),
            _ => return Resolver::resolve(self.source.tree.as_ref(), query),
        };
        let tree = &self.source.tree;
        let Some(id) = tree
            .lookup_type(owner)
            .and_then(|id| tree.resolve(id, name, MemberKind::Var))
        else {
            return ResolvedMeaning::Unsupported(query);
        };
        let member = tree.member(id).expect("resolved member belongs to tree");
        if member.metadata.inherited_opaque.is_some() {
            return ResolvedMeaning::Unsupported(query);
        }
        if !constant_query && member.metadata.flags & 2 == 0 {
            return Resolver::resolve(tree.as_ref(), query);
        }
        let actual_owner = tree
            .type_node(member.owner)
            .expect("member owner belongs to tree")
            .path;
        let value = self
            .outcome(ScalarQuery::Const { owner, name })
            .or_else(|| {
                self.outcome(ScalarQuery::Const {
                    owner: actual_owner,
                    name,
                })
            });
        let Some(ScalarOutcome::Value(value)) = value else {
            return ResolvedMeaning::Unsupported(query);
        };
        let mut data = member.metadata.as_ref().clone();
        data.resolved_constant = Some(value.clone());
        let mut bytes = b"dm-scalar-member-v1\0".to_vec();
        bytes.extend_from_slice(&member.content.to_le_bytes());
        bytes.extend_from_slice(&crate::metadata_fingerprint(&data).to_le_bytes());
        bytes.extend_from_slice(&self.backend_identity.to_le_bytes());
        ResolvedMeaning::Member {
            owner: actual_owner,
            name,
            fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes),
            data: Arc::new(data),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{FileId, SymbolTable};
    fn snapshot(source: &str) -> TreeSnapshot {
        crate::from_ast(
            &dm_syntax::parse(source),
            SymbolTable::default(),
            FileId(0),
            0,
            0,
        )
        .unwrap()
        .finish()
        .unwrap()
    }
    fn query(owner: &str, name: &str) -> ScalarQuery {
        ScalarQuery::Const {
            owner: SymbolId::of(owner),
            name: SymbolId::of(name),
        }
    }
    fn number(value: f32) -> ScalarOutcome {
        ScalarOutcome::Value(SemanticValue::NumberBits(value.to_bits()))
    }
    fn backend_disabled() -> ScalarBackend<'static> {
        ScalarBackend {
            identity: 1,
            decode_string: &|_| None,
            nameof: &|_| None,
        }
    }
    #[test]
    fn forward_const_dependencies_and_short_circuit_are_demand_driven() {
        let source=snapshot("/datum/probe\n    var/const/a = b * 2 + 1\n    var/const/b = 5\n    var/const/unused = list(1)\n    var/const/short = 1 || a_cycle\n    var/const/a_cycle = a_cycle\n");
        let a = query("/datum/probe", "a");
        let short = query("/datum/probe", "short");
        let result = resolve(&source, &[a, short], &backend_disabled());
        assert_eq!(result.outcome(a), Some(&number(11.0)));
        assert_eq!(result.outcome(short), Some(&number(1.0)));
        assert_eq!(result.outcomes.len(), 3);
        assert!(!result
            .outcomes
            .contains_key(&query("/datum/probe", "unused")));
        assert!(!result
            .outcomes
            .contains_key(&query("/datum/probe", "a_cycle")));
        assert_eq!(
            result.dependencies.get(&a).unwrap().as_ref(),
            &[query("/datum/probe", "b")]
        );
        let meaning = Resolver::resolve(
            &result,
            ResolveQuery::Constant {
                owner: SymbolId::of("/datum/probe"),
                name: SymbolId::of("a"),
            },
        );
        assert!(
            matches!(meaning,ResolvedMeaning::Member {data,..} if data.resolved_constant==Some(SemanticValue::NumberBits(11.0f32.to_bits())))
        );
        assert_eq!(
            source
                .tree
                .member(
                    source
                        .tree
                        .resolve(
                            source
                                .tree
                                .lookup_type(SymbolId::of("/datum/probe"))
                                .unwrap(),
                            SymbolId::of("a"),
                            MemberKind::Var
                        )
                        .unwrap()
                )
                .unwrap()
                .metadata
                .resolved_constant,
            None
        );
    }
    #[test]
    fn cycles_and_unsupported_values_are_not_null_or_missing() {
        let source=snapshot("/datum/probe\n    var/const/a = b\n    var/const/b = a\n    var/const/items = list(1,2)\n    var/const/asset = 'asset.txt'\n    var/const/runtime = rand(1,2)\n    var/const/none = null\n");
        let a = query("/datum/probe", "a");
        let b = query("/datum/probe", "b");
        let result = resolve(
            &source,
            &[
                a,
                b,
                query("/datum/probe", "items"),
                query("/datum/probe", "asset"),
                query("/datum/probe", "runtime"),
                query("/datum/probe", "none"),
            ],
            &backend_disabled(),
        );
        assert!(matches!(result.outcome(a),Some(ScalarOutcome::Cycle(cycle)) if cycle.len()==2));
        assert_eq!(result.outcome(a), result.outcome(b));
        for name in ["items", "asset", "runtime"] {
            assert!(matches!(
                result.outcome(query("/datum/probe", name)),
                Some(ScalarOutcome::Unsupported(_))
            ));
        }
        assert_eq!(
            result.outcome(query("/datum/probe", "none")),
            Some(&ScalarOutcome::Value(SemanticValue::Null))
        );
        let reordered = resolve(
            &source,
            &[
                b,
                a,
                query("/datum/probe", "none"),
                query("/datum/probe", "runtime"),
                query("/datum/probe", "asset"),
                query("/datum/probe", "items"),
            ],
            &backend_disabled(),
        );
        assert_eq!(result.identity, reordered.identity);
    }
    #[test]
    fn declaration_default_keeps_formal_lexical_scope_apart_from_class_assignment() {
        let source=snapshot("/datum/base\n    var/const/seed = 2\n    var/value = seed + 1\n/datum/base/child\n    var/const/seed = 20\n    value = seed + 4\n");
        let owner = SymbolId::of("/datum/base/child");
        let name = SymbolId::of("value");
        let declared = ScalarQuery::DeclaredDefault { owner, name };
        let effective = ScalarQuery::EffectiveDefault { owner, name };
        let result = resolve(&source, &[declared, effective], &backend_disabled());
        assert_eq!(result.outcome(declared), Some(&number(3.0)));
        assert_eq!(result.outcome(effective), Some(&number(24.0)));
    }
    #[test]
    fn backend_policy_is_explicit_and_exact_bytes_qualify_overlay_identity() {
        let source = snapshot(
            "/datum/probe\n    var/const/text = \"value\"\n    var/const/named = nameof(text)\n",
        );
        let decoder = |_: &str| Some(vec![0xff, 0x80]);
        let nameof = |_: &Expr| Some("chosen".into());
        let backend = ScalarBackend {
            identity: 123,
            decode_string: &decoder,
            nameof: &nameof,
        };
        let text = query("/datum/probe", "text");
        let named = query("/datum/probe", "named");
        let result = resolve(&source, &[text, named], &backend);
        assert_eq!(
            result.outcome(text),
            Some(&ScalarOutcome::Value(SemanticValue::Text(Arc::from([
                0xff, 0x80
            ]))))
        );
        assert_eq!(
            result.outcome(named),
            Some(&ScalarOutcome::Value(SemanticValue::Text(Arc::from(
                b"chosen".as_slice()
            ))))
        );
        let changed_backend = ScalarBackend {
            identity: 124,
            decode_string: &decoder,
            nameof: &nameof,
        };
        assert_ne!(
            result.identity,
            resolve(&source, &[text, named], &changed_backend).identity
        );
        assert!(matches!(
            resolve(&source, &[text], &backend_disabled()).outcome(text),
            Some(ScalarOutcome::Unsupported(
                UnsupportedReason::BackendInterpretation
            ))
        ));
    }
    #[test]
    fn opaque_inherited_defaults_are_unsupported_but_authored_effective_expression_is_exact() {
        let source = "/datum/probe\n    value = 9\n";
        let mut symbols = SymbolTable::default();
        for name in ["/datum/probe", "value"] {
            symbols.intern(name).unwrap();
        }
        let adapted = crate::from_ast(&dm_syntax::parse(source), symbols, FileId(0), 0, 0).unwrap();
        let fields = vec![dm_ir::OpaqueFieldBase {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("value"),
            declared_type: dm_ir::DeclaredTypeKnowledge::Unsupported,
        }];
        let tree = crate::build_with_intrinsic_fields(adapted.symbols, &adapted.skeletons, &fields)
            .unwrap();
        let occurrences = crate::OccurrenceTable::build(&tree, adapted.origins).unwrap();
        let source = TreeSnapshot {
            tree: Arc::new(tree),
            occurrences: Arc::new(occurrences),
        };
        let owner = SymbolId::of("/datum/probe");
        let name = SymbolId::of("value");
        let declared = ScalarQuery::DeclaredDefault { owner, name };
        let effective = ScalarQuery::EffectiveDefault { owner, name };
        let result = resolve(&source, &[declared, effective], &backend_disabled());
        assert_eq!(
            result.outcome(declared),
            Some(&ScalarOutcome::Unsupported(
                UnsupportedReason::OpaqueInheritedMetadata
            ))
        );
        assert_eq!(result.outcome(effective), Some(&number(9.0)));
        let query = ResolveQuery::Var { owner, name };
        assert_eq!(
            Resolver::resolve(&result, query),
            ResolvedMeaning::Unsupported(query)
        );
    }
}
