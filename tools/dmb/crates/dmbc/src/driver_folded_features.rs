//! Metadata for references actually visited by the captured constant evaluator.
use super::*;
impl DriverEvaluator<'_> {
    pub(super) fn nameof_source_features(
        &self,
        owner: SymbolId,
        procedure: Option<dm_ir::ProcedureIdentity>,
        lexical_static: Option<dm_ir::ProcedureStaticIdentity>,
        expression: &dm_syntax::Expr,
        typed_failure: Option<&RefCell<Option<dm_codegen_byond::LowerError>>>,
    ) -> Result<dm_codegen_byond::SourceFeatures, String> {
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
        let locals = if let Some(identity) = lexical_static {
            if Some(identity.procedure) != procedure {
                return Err("folded reference static context mismatch".into());
            }
            let query = ResolveQuery::ProcedureStatic {
                procedure: identity.procedure,
                name: identity.name,
            };
            let ResolvedMeaning::ProcedureStatic(declaration) = self.resolver.resolve(query) else {
                return Err("folded reference lexical declaration is not captured".into());
            };
            if declaration.identity != identity {
                return Err("folded reference lexical declaration identity mismatch".into());
            }
            declaration
                .lexical_locals
                .iter()
                .map(|(name, path)| {
                    Ok((
                        self.symbols
                            .text(*name)
                            .ok_or("folded lexical local spelling unavailable")?
                            .to_owned(),
                        path.map(|path| {
                            self.symbols
                                .text(path)
                                .map(str::to_owned)
                                .ok_or("folded lexical local type spelling unavailable")
                        })
                        .transpose()?,
                    ))
                })
                .collect::<Result<Vec<_>, String>>()?
        } else {
            Vec::new()
        };
        dm_codegen_byond::observe_reference_source_features_with_lexical_locals(
            expression,
            &bindings,
            self.symbols,
            self.resolver,
            &locals,
        )
        .map_err(|error| {
            let message = format!("folded reference feature proof: {error:?}");
            if let Some(failure) = typed_failure {
                let mut failure = failure.borrow_mut();
                if failure.is_none() {
                    *failure = Some(error);
                }
            }
            message
        })
    }
}
