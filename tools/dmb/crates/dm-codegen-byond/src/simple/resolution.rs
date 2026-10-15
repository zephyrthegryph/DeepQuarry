//! Resolution lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn debug_at(&mut self, offset: usize, raw: &str) -> Result<(), LowerError> {
        self.statement_span = Some(LowerSpan {
            start: offset,
            end: offset + raw.len(),
        });
        if let Some(provider) = self.debug {
            let ordinal = provider
                .ordinal(offset)
                .map_err(|reason| error(raw, &reason))?;
            self.debug_current = Some(ordinal);
        }
        Ok(())
    }
    pub(super) fn class_tag(&self, path: &str) -> Result<Option<u8>, LowerError> {
        let Some(lookup) = self.lookup else {
            return Ok(class_tag(path));
        };
        let runtime_type = self.semantic(lookup.runtime_type(path))?;
        let query = dm_ir::ResolveQuery::Ancestry(runtime_type);
        match self.semantic(lookup.answer(query))? {
            dm_ir::ResolvedMeaning::Missing => Ok(None),
            dm_ir::ResolvedMeaning::Symbols(ancestors) => {
                for &ancestor in ancestors.iter() {
                    let name = self.semantic(lookup.text(query, ancestor))?;
                    if name.trim_start_matches('/').contains('/') {
                        continue;
                    }
                    // `/atom` itself is tagged as the non-movable atom family (10, like `/turf`);
                    // its descendants (`/atom/movable`, `/obj`) inherit the movable tag.
                    if ancestor == runtime_type && name.trim_start_matches('/') == "atom" {
                        return Ok(Some(ATOM_ROOT_TAG));
                    }
                    if let Some(tag) = family_tag(&name) {
                        return Ok(Some(tag));
                    }
                }
                Ok(None)
            }
            _ => self.semantic(Err(lookup.error(query, "invalid ancestry answer"))),
        }
    }
    pub(super) fn semantic<T>(&self, result: Result<T, LowerError>) -> Result<T, LowerError> {
        let result = result.map_err(|error| error.at(self.statement_span));
        if let Err(error) = &result {
            self.resolver_failure
                .borrow_mut()
                .get_or_insert_with(|| error.clone());
        }
        result
    }
    pub(super) fn has_field(&self, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => {
                // Captured lexical statics shadow instance fields. Resolve this
                // before a class-storage query, whose intrinsic coverage may be partial.
                if self
                    .semantic(lookup.procedure_static(self.bindings.procedure_identity, name))?
                    .is_some()
                {
                    return Ok(false);
                }
                match &self.bindings.current_type_path {
                    Some(owner) => {
                        if self.member_global(owner, name)?.is_some() {
                            return Ok(false);
                        }
                        self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                            owner: dm_ir::SymbolId::of(owner),
                            name: dm_ir::SymbolId::of(name),
                        }))
                    }
                    None => Ok(false),
                }
            }
            None => Ok(self.bindings.has_field(name)),
        }
    }
    pub(super) fn has_global(&self, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(
                lookup.presence(dm_ir::ResolveQuery::GlobalVar(dm_ir::SymbolId::of(name))),
            ),
            None => Ok(self.bindings.has_global(name)),
        }
    }
    pub(super) fn has_global_proc(&self, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(
                lookup.presence(dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of(name))),
            ),
            None => Ok(self.bindings.has_global_proc(name)),
        }
    }
    pub(super) fn has_visible_global(&self, name: &str) -> Result<bool, LowerError> {
        if let Some(lookup) = self.lookup {
            if self
                .semantic(lookup.procedure_static(self.bindings.procedure_identity, name))?
                .is_some()
            {
                return Ok(true);
            }
        }
        if self.lookup.is_some() {
            if let Some(owner) = self.bindings.current_type_path.as_deref() {
                if self.member_global(owner, name)?.is_some() {
                    return Ok(true);
                }
            }
        }
        self.has_global(name)
    }
    pub(super) fn declared_type_text(
        &self,
        query: dm_ir::ResolveQuery,
    ) -> Result<Option<String>, LowerError> {
        let lookup = self
            .lookup
            .expect("typed declaration lookup needs resolver");
        let id = self.semantic(lookup.declared_type(query))?;
        id.map(|id| self.semantic(lookup.text(query, id)))
            .transpose()
    }
    pub(super) fn procedure_return_type_text(
        &self,
        query: dm_ir::ResolveQuery,
    ) -> Result<Option<String>, LowerError> {
        let lookup = self.lookup.expect("typed return lookup needs resolver");
        let id = self.semantic(lookup.procedure_return_type(query))?;
        id.map(|id| self.semantic(lookup.text(query, id)))
            .transpose()
    }
    pub(super) fn global_proc(&self, name: &str) -> Result<SymRef, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.procedure_literal(&format!("/proc/{name}"))),
            None => self
                .bindings
                .global_proc(name)
                .ok_or_else(|| error(name, "global procedure has no captured identity")),
        }
    }
    pub(super) fn procedure_literal(&self, path: &str) -> Result<SymRef, LowerError> {
        if let Some(lookup) = self.lookup {
            return self.semantic(lookup.procedure_literal(path));
        }
        let (owner, name, verb) = if let Some((owner, name)) = path.rsplit_once("/proc/") {
            (owner, name, false)
        } else if let Some((owner, name)) = path.rsplit_once("/verb/") {
            (owner, name, true)
        } else {
            return Err(error(path, "procedure literal has no namespace"));
        };
        let reference = if owner.is_empty() {
            self.bindings.global_proc(name)
        } else {
            self.bindings.member_proc(owner, name)
        }
        .ok_or_else(|| error(path, "procedure literal has no captured identity"))?;
        if verb != matches!(reference, SymRef::Verb { .. }) {
            return Err(error(
                path,
                "procedure literal namespace differs from captured identity",
            ));
        }
        Ok(reference)
    }
    pub(super) fn current_procedure_value(&self, statement: &str) -> Result<SymRef, LowerError> {
        let identity = self.bindings.procedure_identity.ok_or_else(|| {
            error(
                statement,
                "__PROC__ requires exact current procedure identity",
            )
        })?;
        if let Some(lookup) = self.lookup {
            return self.semantic(lookup.procedure_value_key(identity));
        }
        Ok(if identity.verb {
            SymRef::Verb {
                owner: identity.owner,
                name: identity.name,
                occurrence: identity.occurrence,
            }
        } else {
            SymRef::Proc {
                owner: identity.owner,
                name: identity.name,
                occurrence: identity.occurrence,
            }
        })
    }

    pub(super) fn global_variable(&self, name: &str) -> Result<SymRef, LowerError> {
        self.bindings
            .global_variable(name)
            .ok_or_else(|| error(name, "global variable has no captured identity"))
    }

    pub(super) fn field_type(&self, name: &str) -> Result<Option<String>, LowerError> {
        match (self.lookup, self.bindings.current_type_path.as_deref()) {
            (Some(_), Some(owner)) => {
                self.declared_type_text(dm_ir::ResolveQuery::DeclaredVarType {
                    owner: dm_ir::SymbolId::of(owner),
                    name: dm_ir::SymbolId::of(name),
                })
            }
            (Some(_), None) => Ok(None),
            (None, _) => Ok(self.bindings.field_type(name).map(str::to_owned)),
        }
    }
    pub(super) fn global_type(&self, name: &str) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(_) => self.declared_type_text(dm_ir::ResolveQuery::GlobalVar(SymbolId::of(name))),
            None => Ok(self.bindings.global_type(name).map(str::to_owned)),
        }
    }
    pub(super) fn member_type(
        &self,
        owner: &str,
        name: &str,
    ) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(_) => self.declared_type_text(dm_ir::ResolveQuery::DeclaredVarType {
                owner: dm_ir::SymbolId::of(owner),
                name: dm_ir::SymbolId::of(name),
            }),
            None => Ok(self.bindings.member_type(owner, name).map(str::to_owned)),
        }
    }
    pub(super) fn member_global(
        &self,
        owner: &str,
        name: &str,
    ) -> Result<Option<SymRef>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.slot(dm_ir::ResolveQuery::VarStorage {
                owner: dm_ir::SymbolId::of(owner),
                name: dm_ir::SymbolId::of(name),
            })),
            None => Ok(self.bindings.member_global(owner, name)),
        }
    }
    pub(super) fn unique_member_global(&self, name: &str) -> Result<Option<SymRef>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.slot(dm_ir::ResolveQuery::UniqueStaticVar(
                dm_ir::SymbolId::of(name),
            ))),
            None => Ok(self.bindings.unique_member_global(name)),
        }
    }
    pub(super) fn fallback_member_global(
        &self,
        object: &Expr,
        name: &str,
        via_colon: bool,
    ) -> Result<Option<SymRef>, LowerError> {
        if via_colon {
            return Ok(None);
        }
        if let Some(lookup) = self.lookup {
            if let Some(owner) = self.inferred_expression_type(object)? {
                let query = dm_ir::ResolveQuery::VarStorage {
                    owner: dm_ir::SymbolId::of(&owner),
                    name: dm_ir::SymbolId::of(name),
                };
                match self.semantic(lookup.answer(query))? {
                    dm_ir::ResolvedMeaning::InstanceField { .. } => return Ok(None),
                    dm_ir::ResolvedMeaning::Slot { .. } => {
                        return self.semantic(lookup.slot(query))
                    }
                    dm_ir::ResolvedMeaning::Missing => (),
                    _ => return Err(error("member selector", "invalid variable storage answer")),
                }
            }
        }
        self.unique_member_global(name)
    }
    pub(super) fn member_proc(
        &self,
        owner: &str,
        name: &str,
    ) -> Result<Option<SymRef>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.member_proc(owner, name)),
            None => Ok(self.bindings.member_proc(owner, name)),
        }
    }
    pub(super) fn has_declared_member_proc(
        &self,
        owner: &str,
        name: &str,
    ) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberProc {
                owner: dm_ir::SymbolId::of(owner),
                name: dm_ir::SymbolId::of(name),
            })),
            None => Ok(self.bindings.has_declared_member_proc(owner, name)),
        }
    }
    pub(super) fn numeric_constant(&self, name: &str) -> Result<Option<u32>, LowerError> {
        if let Some(lookup) = self.lookup {
            let value = self.semantic(lookup.constant(name))?;
            return self.predefined_projection(
                lookup,
                name,
                dm_ir::predefined_resolution::numeric_value(value),
            );
        }
        Ok(self
            .bindings
            .shared
            .as_ref()
            .and_then(|shared| shared.numeric_constants.get(name))
            .copied())
    }
    pub(super) fn string_constant(&self, name: &str) -> Result<Option<String>, LowerError> {
        if let Some(lookup) = self.lookup {
            let value = self.semantic(lookup.constant(name))?;
            return self.predefined_projection(
                lookup,
                name,
                dm_ir::predefined_resolution::text_value(value),
            );
        }
        Ok(self
            .bindings
            .shared
            .as_ref()
            .and_then(|shared| shared.string_constants.get(name))
            .cloned())
    }
    pub(super) fn statement_visible(&self, statement: &Statement) -> bool {
        self.statement_mask
            .is_none_or(|mask| mask.visible(statement))
    }
    pub(super) fn statement_view<'s>(
        &'s self,
        statements: &'s [Statement],
    ) -> dm_syntax::StatementView<'s> {
        match self.statement_mask {
            Some(mask) => dm_syntax::StatementView::masked(statements, mask),
            None => dm_syntax::StatementView::all(statements),
        }
    }
    pub(super) fn prepare_user_labels(
        &mut self,
        statements: &[Statement],
        depth: usize,
    ) -> Result<(), LowerError> {
        let mut seen = BTreeSet::new();
        for statement in statements {
            if !self.statement_visible(statement) {
                continue;
            }
            if let StatementKind::Label { name, .. } = &statement.kind {
                if name.is_empty()
                    || !name.chars().all(|ch| ch.is_alphanumeric() || ch == '_')
                    || !seen.insert(name.clone())
                {
                    let mut failure = error(&statement.raw_header, "invalid or duplicate label")
                        .at(Some(LowerSpan {
                            start: statement.header_span.start,
                            end: statement.header_span.end,
                        }));
                    failure.kind = LowerErrorKind::SourceError;
                    return Err(failure);
                }
                let label = self.label();
                self.label_try_depths.insert(label, depth);
                self.user_labels.insert(name.clone(), label);
                self.user_label_iterator_depths
                    .insert(name.clone(), self.iterator_depth);
            }
        }
        Ok(())
    }

    /// One borrowed initializer write: occurrence belongs to the issued unit,
    /// while every expression span remains in the authored immutable AST.
    pub(super) fn typed_assignment_continuation(
        &mut self,
        target: &Expr,
        value: &Expr,
        occurrence: dm_syntax::Span,
        double_receiver: bool,
        continuation: Option<crate::initializer::ValueContinuation<'_>>,
    ) -> Result<(), LowerError> {
        if let Some(extra) =
            continuation.filter(|extra| extra.before_assignment && !extra.assignment_is_allocation)
        {
            self.typed_array_continuation(extra.dimensions, occurrence, None)?;
        }
        let emit_assignment = continuation.is_none_or(|extra| extra.emit_assignment);
        if emit_assignment {
            if let Some(extra) = continuation.filter(|extra| extra.assignment_is_allocation) {
                self.typed_array_continuation(extra.dimensions, occurrence, Some(target))?;
            } else {
                self.typed_assignment(target, value, occurrence)?;
            }
            if double_receiver
                && !crate::initializer::finish::double_assignment_receiver(
                    &mut self.result.code.items,
                )
            {
                return Err(error(
                    "initializer assignment",
                    "declared instance target receiver could not be certified",
                ));
            }
        }
        if let Some(extra) =
            continuation.filter(|extra| !extra.before_assignment && !extra.assignment_is_allocation)
        {
            self.typed_array_continuation(extra.dimensions, occurrence, None)?;
        }
        Ok(())
    }
    pub(super) fn typed_array_continuation(
        &mut self,
        dimensions: &[u16],
        occurrence: dm_syntax::Span,
        target: Option<&Expr>,
    ) -> Result<(), LowerError> {
        let saved_debug = self.debug_current;
        let saved_span = self.statement_span;
        let dimensions = dimensions.iter().map(u16::to_string).collect::<Vec<_>>();
        let borrowed = dimensions.iter().map(String::as_str).collect::<Vec<_>>();
        let result = self
            .debug_at(occurrence.start, "initializer allocation")
            .and_then(|()| {
                let target = target
                    .map(|target| self.variable_expr(target, "initializer allocation"))
                    .transpose()?;
                if let Some(target) = &target {
                    self.ensure_writable(target, "initializer allocation")?;
                }
                self.local_array(&borrowed, "initializer allocation")?;
                if let Some(target) = target {
                    self.emit(opcode::SET_VAR, vec![Word::Variable(target)]);
                }
                Ok(())
            })
            .map_err(|error| error.at(self.statement_span));
        self.debug_current = saved_debug;
        self.statement_span = saved_span;
        result
    }
    pub(super) fn typed_assignment(
        &mut self,
        target: &Expr,
        value: &Expr,
        occurrence: dm_syntax::Span,
    ) -> Result<(), LowerError> {
        let saved_debug = self.debug_current;
        let saved_span = self.statement_span;
        let saved_slots = self.local_slots.checkpoint();
        let saved_types = self.local_types.checkpoint();
        let result = self
            .debug_at(occurrence.start, "initializer assignment")
            .and_then(|()| self.assign_expr(target, "=", value, "initializer assignment"))
            .map_err(|error| error.at(self.statement_span));
        self.debug_current = saved_debug;
        self.statement_span = saved_span;
        self.local_slots.restore(saved_slots);
        self.local_types.restore(saved_types);
        result
    }
    pub(super) fn typed_statements(&mut self, statements: &[Statement]) -> Result<(), LowerError> {
        let saved_coordinates = self.diagnostic_expression_coordinates;
        self.diagnostic_expression_coordinates = true;
        let saved_debug = self.debug_current;
        let saved_span = self.statement_span;
        let saved_slots = self.local_slots.checkpoint();
        let saved_types = self.local_types.checkpoint();
        let saved_labels = self.user_labels.clone();
        let saved_label_iterator_depths = self.user_label_iterator_depths.clone();
        let saved_breaks = self.label_breaks.clone();
        let saved_depths = self.label_loop_depths.clone();
        let saved_iterator_depths = self.label_iterator_depths.clone();
        let result = self
            .prepare_user_labels(statements, self.try_depth)
            .and_then(|()| self.typed_statements_inner(statements))
            .map_err(|error| error.at(self.statement_span));
        self.debug_current = saved_debug;
        self.diagnostic_expression_coordinates = saved_coordinates;
        self.statement_span = saved_span;
        self.local_slots.restore(saved_slots);
        self.local_types.restore(saved_types);
        self.user_labels = saved_labels;
        self.user_label_iterator_depths = saved_label_iterator_depths;
        self.label_breaks = saved_breaks;
        self.label_loop_depths = saved_depths;
        self.label_iterator_depths = saved_iterator_depths;
        result
    }
}
