use super::*;
#[derive(Default)]
pub(super) struct Memo {
    pub(super) certificates: BTreeMap<ScalarQuery, u64>,
    pub(super) values: BTreeMap<ScalarQuery, ScalarOutcome>,
    pub(super) active: Vec<ScalarQuery>,
    pub(super) edges: BTreeMap<ScalarQuery, BTreeSet<ScalarQuery>>,
    pub(super) predefined: BTreeMap<SymbolId, PredefinedOutcome>,
    reads:
        BTreeMap<ScalarQuery, dm_session::ObservationLedger<ScalarReadQuery, ScalarReadAnswer, ()>>,
    pub(super) cyclic: BTreeSet<ScalarQuery>,
    inserted: Vec<ScalarQuery>,
    predefined_changes: Vec<(SymbolId, Option<PredefinedOutcome>)>,
}
pub(super) struct Pass<'a> {
    pub(super) tree: &'a SemanticTree,
    pub(super) backend: &'a ScalarBackend<'a>,
    pub(super) memo: RefCell<Memo>,
    pub(super) predefined: Option<&'a dyn Resolver>,
    pub(super) calls: Option<&'a dyn PureCalls>,
    pub(super) artifacts: Option<&'a dyn ScalarArtifacts>,
}
impl Pass<'_> {
    fn member(&self, owner: SymbolId, name: SymbolId) -> Option<MemberId> {
        self.observe(ScalarReadQuery::Member { owner, name });
        self.tree
            .lookup_type(owner)
            .and_then(|owner| self.tree.resolve(owner, name, MemberKind::Var))
    }
    pub(super) fn query(&self, query: ScalarQuery) -> ScalarOutcome {
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
        let checkpoint = {
            let memo = self.memo.borrow();
            (memo.inserted.len(), memo.predefined_changes.len())
        };
        self.observe(ScalarReadQuery::PurePolicy);
        let cached = self
            .artifacts
            .and_then(|artifacts| artifacts.lookup(query, &|read| self.answer(read)));
        if cached.is_none() {
            let mut memo = self.memo.borrow_mut();
            while memo.inserted.len() > checkpoint.0 {
                let inserted = memo.inserted.pop().unwrap();
                memo.values.remove(&inserted);
                memo.certificates.remove(&inserted);
                memo.edges.remove(&inserted);
                memo.reads.remove(&inserted);
            }
            while memo.predefined_changes.len() > checkpoint.1 {
                let (name, old) = memo.predefined_changes.pop().unwrap();
                if let Some(old) = old {
                    memo.predefined.insert(name, old);
                } else {
                    memo.predefined.remove(&name);
                }
            }
            memo.reads.remove(&query);
        }
        let reused = cached.is_some();
        let value = if let Some(cached) = cached {
            let mut memo = self.memo.borrow_mut();
            if cached.dependencies.is_empty() {
                memo.edges.remove(&query);
            } else {
                memo.edges
                    .insert(query, cached.dependencies.iter().copied().collect());
            }
            for (name, value) in cached.predefined.iter() {
                let old = memo.predefined.insert(*name, value.clone());
                memo.predefined_changes.push((*name, old));
            }
            if let Some(certificate) = cached.certificate() {
                memo.certificates.insert(query, certificate);
            }
            cached.outcome.clone()
        } else {
            self.observe(ScalarReadQuery::PurePolicy);
            self.evaluate(query)
        };
        let mut memo = self.memo.borrow_mut();
        if self.artifacts.is_some()
            && (matches!(value, ScalarOutcome::Cycle(_)) || memo.cyclic.contains(&query))
        {
            let active = memo.active.clone();
            for active in &active {
                memo.certificates.remove(active);
            }
            memo.cyclic.extend(active);
        }
        if !reused && !memo.cyclic.contains(&query) {
            if let Some(artifacts) = self.artifacts {
                let reads = memo
                    .reads
                    .get(&query)
                    .map(|ledger| ledger.reads())
                    .unwrap_or_default();
                let dependencies = memo
                    .edges
                    .get(&query)
                    .map(|edges| edges.iter().copied().collect::<Vec<_>>())
                    .unwrap_or_default()
                    .into();
                let predefined = reads
                    .iter()
                    .filter_map(|read| match (&read.query, &read.answer) {
                        (
                            ScalarReadQuery::Predefined(name),
                            ScalarReadAnswer::Predefined(answer),
                        ) => Some((*name, answer.clone())),
                        _ => None,
                    })
                    .collect::<Vec<_>>()
                    .into();
                let admitted = artifacts.remember_certified(
                    query,
                    ScalarArtifact::captured(value.clone(), dependencies, predefined),
                    reads
                        .iter()
                        .map(|read| (read.query.clone(), read.answer.clone()))
                        .collect(),
                );
                if let Some(certificate) = admitted.and_then(|value| value.certificate()) {
                    memo.certificates.insert(query, certificate);
                }
            }
        }
        drop(memo);
        let mut memo = self.memo.borrow_mut();
        memo.active.pop();
        memo.values.insert(query, value.clone());
        if self.artifacts.is_some() {
            memo.inserted.push(query);
        }
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
        if self.artifacts.is_some() {
            for token in expression.tokens.iter() {
                self.spelling(token.text);
            }
        }
        let Some(text) = expression.source_text(self.tree.symbols()) else {
            return ScalarOutcome::Unsupported(UnsupportedReason::RuntimeOrUnsupportedExpression);
        };
        let failure = RefCell::new(None);
        let result = evaluate_with_resources_and_calls(
            &text,
            |name| {
                // The intrinsic is lexical, but authored fields/globals retain
                // ordinary identifier shadowing precedence.
                if name == "__TYPE__" {
                    let lexical_owner = self.tree.type_node(scope)?.path;
                    let symbol = SymbolId::of(name);
                    if self.member(lexical_owner, symbol).is_none()
                        && self.member(SymbolId::of("/"), symbol).is_none()
                    {
                        if lexical_owner == SymbolId::of("/") {
                            return Some(Constant::Null);
                        }
                        if !matches!(self.meaning(ResolveQuery::Type(lexical_owner)),
                            ResolvedMeaning::Symbol(found) if found == lexical_owner)
                        {
                            *failure.borrow_mut() =
                                Some(ScalarOutcome::Unsupported(UnsupportedReason::UnknownType));
                            return None;
                        }
                        return self
                            .spelling(lexical_owner)
                            .map(|path| Constant::TypePath(path.to_string()));
                    }
                }
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
                let dependency_value = self.query(dependency);
                self.record(
                    ScalarReadQuery::Dependency(dependency),
                    ScalarReadAnswer::Dependency(dependency_value.clone()),
                );
                match dependency_value {
                    ScalarOutcome::Value(value) => self.to_constant(&value),
                    ScalarOutcome::Unsupported(UnsupportedReason::MissingDeclaration)
                        if !name.contains("::") && self.predefined.is_some() =>
                    {
                        let symbol = SymbolId::of(name);
                        let outcome = match self
                            .predefined
                            .unwrap()
                            .resolve(ResolveQuery::PredefinedConstant(symbol))
                        {
                            ResolvedMeaning::Value(value) => PredefinedOutcome::Value(value),
                            ResolvedMeaning::Missing => PredefinedOutcome::Missing,
                            _ => PredefinedOutcome::Unsupported,
                        };
                        self.record(
                            ScalarReadQuery::Predefined(symbol),
                            ScalarReadAnswer::Predefined(outcome.clone()),
                        );
                        let mut memo = self.memo.borrow_mut();
                        let old = memo.predefined.insert(symbol, outcome.clone());
                        if self.artifacts.is_some() {
                            memo.predefined_changes.push((symbol, old));
                        }
                        drop(memo);
                        match outcome {
                            PredefinedOutcome::Value(value) => self.to_constant(&value),
                            _ => {
                                *failure.borrow_mut() = Some(ScalarOutcome::Unsupported(
                                    UnsupportedReason::MissingDeclaration,
                                ));
                                None
                            }
                        }
                    }
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
            |_| None,
            self.calls,
        );
        match result {
            Err(error) => failure
                .into_inner()
                .unwrap_or(ScalarOutcome::RejectedPureCall(error)),
            Ok(Some(value)) => self.to_semantic(value).map_or(
                ScalarOutcome::Unsupported(UnsupportedReason::UnknownType),
                ScalarOutcome::Value,
            ),
            Ok(None) => failure.into_inner().unwrap_or(ScalarOutcome::Unsupported(
                UnsupportedReason::RuntimeOrUnsupportedExpression,
            )),
        }
    }
}

impl Pass<'_> {
    fn record(&self, query: ScalarReadQuery, answer: ScalarReadAnswer) {
        if self.artifacts.is_none() {
            return;
        }
        let memo = self.memo.borrow();
        let active = memo.active.last().copied();
        drop(memo);
        if let Some(active) = active {
            self.memo
                .borrow_mut()
                .reads
                .entry(active)
                .or_default()
                .record(query, answer, (), None);
        }
    }
    fn observe(&self, query: ScalarReadQuery) {
        if self.artifacts.is_some() {
            let _ = self.answer(&query);
        }
    }
    fn answer(&self, query: &ScalarReadQuery) -> ScalarReadAnswer {
        let answer = match *query {
            ScalarReadQuery::PurePolicy => ScalarReadAnswer::PurePolicy(
                self.backend.identity,
                self.calls.and_then(|calls| {
                    calls
                        .immutable_policy_identity()
                        .map(|immutable| (calls.identity(), immutable))
                }),
            ),
            ScalarReadQuery::Member { owner, name } => {
                let member = self
                    .tree
                    .lookup_type(owner)
                    .and_then(|id| self.tree.resolve(id, name, MemberKind::Var));
                let value = member.and_then(|id| {
                    let node = self.tree.member(id)?;
                    let actual = self.tree.type_node(node.owner)?.path;
                    let declared = self
                        .tree
                        .override_chain(id)
                        .into_iter()
                        .rev()
                        .find_map(|id| {
                            let node = self.tree.member(id)?;
                            (node.definition == DefinitionMode::Declare)
                                .then(|| self.tree.type_node(node.owner).map(|ty| ty.path))
                                .flatten()
                        })
                        .unwrap_or(actual);
                    Some((actual, declared, Arc::clone(&node.metadata), node.content))
                });
                ScalarReadAnswer::Member(value)
            }
            ScalarReadQuery::Meaning(query) => {
                ScalarReadAnswer::Meaning(Resolver::resolve(self.tree, query))
            }
            ScalarReadQuery::Spelling(symbol) => {
                ScalarReadAnswer::Spelling(self.tree.symbols().text(symbol).map(Arc::from))
            }
            ScalarReadQuery::Predefined(symbol) => {
                let value = self
                    .predefined
                    .map(|host| host.resolve(ResolveQuery::PredefinedConstant(symbol)));
                ScalarReadAnswer::Predefined(match value {
                    Some(ResolvedMeaning::Value(value)) => PredefinedOutcome::Value(value),
                    Some(ResolvedMeaning::Missing) | None => PredefinedOutcome::Missing,
                    _ => PredefinedOutcome::Unsupported,
                })
            }
            ScalarReadQuery::Dependency(query) => ScalarReadAnswer::Dependency(self.query(query)),
        };
        self.record(query.clone(), answer.clone());
        answer
    }
    fn spelling(&self, symbol: SymbolId) -> Option<Arc<str>> {
        match self.answer(&ScalarReadQuery::Spelling(symbol)) {
            ScalarReadAnswer::Spelling(value) => value,
            _ => unreachable!(),
        }
    }
    fn meaning(&self, query: ResolveQuery) -> ResolvedMeaning {
        match self.answer(&ScalarReadQuery::Meaning(query)) {
            ScalarReadAnswer::Meaning(value) => value,
            _ => unreachable!(),
        }
    }
    fn to_constant(&self, value: &SemanticValue) -> Option<Constant> {
        if let SemanticValue::Type(path) = value {
            self.spelling(*path);
        }
        to_constant(value, self.tree)
    }
    fn to_semantic(&self, value: Constant) -> Option<SemanticValue> {
        if let Constant::TypePath(path) = &value {
            if let Some(query) = crate::constants::procedure_literal_query(path) {
                self.meaning(query);
            } else {
                let symbol = SymbolId::of(path);
                self.meaning(ResolveQuery::Type(symbol));
                self.spelling(symbol);
            }
        }
        to_semantic(value, self.tree)
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
        SemanticValue::Procedure(procedure) => Constant::Procedure(*procedure),
        SemanticValue::ModifiedInstance(instance) => Constant::ModifiedInstance(instance.clone()),
        SemanticValue::Resource(path) => Constant::Resource(*path),
        SemanticValue::List(_) => return None,
    })
}
fn to_semantic(value: Constant, tree: &SemanticTree) -> Option<SemanticValue> {
    Some(match value {
        Constant::Null => SemanticValue::Null,
        Constant::Resource(path) => SemanticValue::Resource(path),
        Constant::Procedure(procedure) => SemanticValue::Procedure(procedure),
        Constant::ModifiedInstance(instance) => SemanticValue::ModifiedInstance(instance),
        Constant::Number(value) => SemanticValue::NumberBits(value.to_bits()),
        Constant::Text(text) => SemanticValue::Text(Arc::from(text.as_bytes())),
        Constant::EncodedText(bytes) => SemanticValue::Text(bytes.into()),
        Constant::TypePath(path) => {
            if let Some(query) = crate::constants::procedure_literal_query(&path) {
                return match dm_ir::Resolver::resolve(tree, query) {
                    dm_ir::ResolvedMeaning::Value(value @ SemanticValue::Procedure(_)) => {
                        Some(value)
                    }
                    _ => None,
                };
            }
            let symbol = SymbolId::of(&path);
            tree.lookup_type(symbol)?;
            if tree.symbols().text(symbol) != Some(path.as_str()) {
                return None;
            }
            SemanticValue::Type(symbol)
        }
    })
}
