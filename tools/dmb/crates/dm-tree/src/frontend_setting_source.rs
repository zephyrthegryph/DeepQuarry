//! Original setting token authority on the SAME current native frontend.
//! No body grammar, setting Expr, filesystem read or new semantic table.
use super::*;

pub(crate) struct OriginalSettingSource<'a> {
    frontend: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
    selected_metadata: &'a dm_ir::ProcedureMetadata,
    input: relative_declarations::OriginalSettingTokenInput<'a>,
}
impl<'a> OriginalSettingSource<'a> {
    pub(super) fn frontend(&self) -> &ColdFrontend {
        self.frontend
    }
    pub(super) fn require_expression(
        &self,
        root: &dm_syntax::SettingExpression,
    ) -> std::io::Result<()> {
        if root.current_offset() != self.input.offset
            || !self.input.slots.contains_original(self.input.ordinal, root)
        {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "settings provider returned a foreign original root or projection",
            ));
        }
        Ok(())
    }
    pub(crate) fn token_input(&self) -> &relative_declarations::OriginalSettingTokenInput<'a> {
        &self.input
    }
    /// Nonactivating source-local producer: the eventual native provider must
    /// supply its genuine SAME current QueryDb body admission. Source authority
    /// was issued before this method; slot storage never creates it.
    pub(crate) fn expression(
        &self,
        admission: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<dm_syntax::SettingExpression, dm_syntax::SettingSyntaxFailure> {
        let i = &self.input;
        let root = i.slots.obtain_with_native_observation(
            i.ordinal,
            i.original_owner.settings.len(),
            admission,
            || {
                i.tokens.with_dense_using(admission,|dense|Ok(dm_syntax::prepare_setting_expression_with_original_literal_facts_and_native_observation(i.source,dense,i.original_value,admission,i.literal_owner.original_literal_facts()?))).map_err(dm_syntax::SettingSyntaxFailure::Operational)?
            },
        ).map(|(root,_)|root)?;
        root.project_current(i.offset, i.source.len())
            .map_err(dm_syntax::SettingSyntaxFailure::Operational)
    }
    pub(crate) fn require_current(
        &self,
        frontend: &ColdFrontend,
        occurrence: &BodyOccurrence,
        metadata: &dm_ir::ProcedureMetadata,
    ) -> Result<(), Diagnostic> {
        if !std::ptr::eq(self.frontend, frontend)
            || !std::ptr::eq(self.occurrence, occurrence)
            || !std::ptr::eq(self.selected_metadata, metadata)
        {
            return Err(internal("original setting source owner differs"));
        }
        frontend.body_code(occurrence)?;
        Ok(())
    }
}
impl ColdFrontend {
    pub(crate) fn original_setting_source<'a>(
        &'a self,
        occurrence: &'a BodyOccurrence,
        metadata: &'a dm_ir::ProcedureMetadata,
        expression: &dm_ir::SymbolicExpression,
    ) -> Result<OriginalSettingSource<'a>, Diagnostic> {
        self.compact_body(occurrence)?;
        let index = *self
            .body_by_declaration
            .get(&occurrence.declaration)
            .ok_or_else(|| internal("original setting occurrence unavailable"))?;
        let issued = self
            .issued_bodies
            .get(index)
            .ok_or_else(|| internal("original setting occurrence unavailable"))?;
        if !std::ptr::eq(issued, occurrence) {
            return Err(internal("original setting occurrence is copied or foreign"));
        }
        let selected = self
            .snapshot
            .tree
            .member(occurrence.member)
            .and_then(|node| node.metadata.procedure.as_deref())
            .ok_or_else(|| internal("selected setting metadata unavailable"))?;
        let bound = self
            .issued_settings
            .get(index)
            .and_then(Option::as_deref)
            .ok_or_else(|| internal("original setting metadata binding unavailable"))?;
        if !std::ptr::eq(selected, metadata) || !std::ptr::eq(bound, metadata) {
            return Err(internal(
                "original setting selected metadata is copied or foreign",
            ));
        }
        let ordinal = metadata.settings.iter().position(|node| {
            matches!(node,dm_ir::ProcedureSettingNode::Setting(setting) if std::ptr::eq(&setting.value,expression))
        }).ok_or_else(|| internal("setting expression is not the selected original directive"))?;
        let input = self
            .issued_syntax
            .setting_token_input_header_only(occurrence.expanded_span, ordinal)
            .map_err(|error| Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .location(error.span.start)
                    .or_else(|| Some(occurrence.source.clone())),
                message: error.message,
            })?;
        // Source producer metadata can be a distinct Arc after legitimate tree
        // reuse. The PRIVATE current binding above already joins that exact
        // original recipe to the selected immutable runtime metadata; equal
        // arbitrary passed metadata alone can never construct this receipt.
        Ok(OriginalSettingSource {
            frontend: self,
            occurrence,
            selected_metadata: metadata,
            input,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{path::Path, sync::Arc};
    struct Source(String);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    #[derive(Debug)]
    struct NoBody;
    impl BodySyntaxQueries for NoBody {
        fn syntax(&self, _: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
            panic!("original setting source receipt must not demand BodySyntax")
        }
    }
    fn fixture(padding: &str) -> ColdFrontend {
        let source = format!(
            "{padding}/proc/p()\n    set name = \"value\"\n    set waitfor = 0\n    return 1\n"
        );
        build(
            Path::new("settings-source.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(Arc::new(NoBody))
    }
    fn metadata(frontend: &ColdFrontend) -> &dm_ir::ProcedureMetadata {
        frontend
            .snapshot
            .tree
            .member(frontend.bodies[0].member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap()
    }
    fn expression(
        metadata: &dm_ir::ProcedureMetadata,
        ordinal: usize,
    ) -> &dm_ir::SymbolicExpression {
        let dm_ir::ProcedureSettingNode::Setting(setting) = &metadata.settings[ordinal] else {
            panic!("expected actual source directive")
        };
        &setting.value
    }
    #[test]
    fn original_setting_source_borrows_actual_tokens_without_body_demand_and_rejects_copies() {
        let frontend = fixture("");
        let body = &frontend.bodies[0];
        let selected = metadata(&frontend);
        let expr = expression(selected, 0);
        let proof = frontend
            .original_setting_source(body, selected, expr)
            .unwrap();
        proof.require_current(&frontend, body, selected).unwrap();
        let input = proof.token_input();
        assert_eq!(input.ordinal, 0);
        assert_eq!(&frontend.expanded.text[input.value.range()], "\"value\"");
        assert_eq!(
            input
                .tokens
                .iter()
                .map(|t| t.text(input.source))
                .collect::<Vec<_>>(),
            ["\"value\""]
        );
        let copied_body = body.clone();
        assert!(frontend
            .original_setting_source(&copied_body, selected, expr)
            .is_err());
        let copied_metadata = selected.clone();
        assert!(frontend
            .original_setting_source(body, &copied_metadata, expression(&copied_metadata, 0))
            .is_err());
        let copied_expression = expr.clone();
        assert!(frontend
            .original_setting_source(body, selected, &copied_expression)
            .is_err());
        assert!(proof
            .require_current(&frontend, &copied_body, selected)
            .is_err());
    }
    #[test]
    fn original_setting_source_uses_current_offsets_and_foreign_code_cannot_issue_tokens() {
        let first = fixture("");
        let shifted = fixture("// current source padding\n");
        let first_metadata = metadata(&first);
        let shifted_metadata = metadata(&shifted);
        let old = first
            .original_setting_source(
                &first.bodies[0],
                first_metadata,
                expression(first_metadata, 1),
            )
            .unwrap();
        let current = shifted
            .original_setting_source(
                &shifted.bodies[0],
                shifted_metadata,
                expression(shifted_metadata, 1),
            )
            .unwrap();
        assert!(current.token_input().value.start > old.token_input().value.start);
        assert_eq!(
            &shifted.expanded.text[current.token_input().value.range()],
            "0"
        );
        assert!(old
            .require_current(&shifted, &shifted.bodies[0], shifted_metadata)
            .is_err());
        let foreign = shifted.body_code(&shifted.bodies[0]).unwrap();
        assert!(first
            .issued_syntax
            .setting_token_input(first.bodies[0].expanded_span, foreign.identity(), 1)
            .is_err());
    }
}
