//! Metadata for references actually visited by the captured constant evaluator.
use super::*;
impl DriverEvaluator<'_> {
    pub(super) fn nameof_source_features(
        &self,
        owner: SymbolId,
        procedure: Option<dm_ir::ProcedureIdentity>,
        expression: &dm_syntax::Expr,
    ) -> Result<dm_codegen_byond::SourceFeatures, String> {
        // Unrelated nameof spellings issue no feature queries. Groups retain the
        // same selected reference and do not trigger another expression walk.
        let mut reference = expression;
        while let dm_syntax::ExprKind::Group(inner) = &reference.kind {
            reference = inner;
        }
        let name = dm_codegen_byond::nameof_reference(reference);
        if !matches!(name, Some("cpu" | "icon" | "overlays" | "underlays")) {
            return Ok(Default::default());
        }
        let mut bindings = dm_codegen_byond::LowerBindings {
            procedure_identity: procedure,
            current_type_path: Some(
                self.symbols
                    .text(owner)
                    .ok_or("folded reference owner spelling unavailable")?
                    .to_owned(),
            ),
            ..Default::default()
        };
        if let Some(procedure) = procedure {
            let query = ResolveQuery::DeclarationChain {
                owner: procedure.owner,
                name: procedure.name,
                verb: procedure.verb,
            };
            let ResolvedMeaning::Members(chain) = self.resolver.resolve(query) else {
                return Err("folded reference lexical signature is not captured".into());
            };
            let mut matched = false;
            for declaration in chain.iter() {
                let ResolvedMeaning::Declaration { identity, data, .. } = declaration else {
                    return Err("folded reference declaration chain is invalid".into());
                };
                if *identity != procedure {
                    continue;
                }
                if matched {
                    return Err("folded reference lexical signature is ambiguous".into());
                }
                matched = true;
                let metadata = data
                    .procedure
                    .as_ref()
                    .ok_or("folded reference lexical signature unavailable")?;
                for parameter in metadata.signature.parameters.iter() {
                    let name = self
                        .symbols
                        .text(parameter.name)
                        .ok_or("folded reference parameter spelling unavailable")?;
                    bindings.parameters.push(name.into());
                    if let Some(path) = parameter.declared_type {
                        bindings.parameter_types.insert(
                            name.into(),
                            self.symbols
                                .text(path)
                                .ok_or("folded reference parameter type unavailable")?
                                .into(),
                        );
                    }
                }
            }
            if !matched {
                return Err("folded reference lexical signature missing".into());
            }
        }
        dm_codegen_byond::observe_reference_source_features(
            reference,
            &bindings,
            self.symbols,
            self.resolver,
        )
        .map_err(|error| format!("folded reference feature proof: {error:?}"))
    }
}
