//! Argument-source companions use the owning procedure's lexical argument frame.
//! Their semantic identity is owner+argument, never a fabricated callable name.
use crate::{
    debug_sources::{DebugOrigin, DebugOrigins},
    lowering::UnitIdentity,
};
use dm_codegen_byond::{
    ProcedureInputs, lower_resolver::ResolverProc, procedure_abi::ArgumentSourceHelper,
};
use dm_ir::{ProcedureMetadata, Resolver, SymbolTable};
use dm_syntax::{Item, TokenKind};
use dm_tree::frontend::ColdFrontend;
mod header_recipe;
pub(crate) use header_recipe::current_header_modifier;
mod failure;
mod visible_formals;
pub use failure::HelperFailure;

#[derive(Clone)]
pub struct LoweredHelper {
    pub owner: UnitIdentity,
    pub argument: u32,
    pub code: ResolverProc,
    pub debug_origins: DebugOrigins,
}
/// Locate the actual captured source expression in the signature. The typed
/// parameter's relative span is checked against the real expanded header before
/// assigning any debug provenance to the companion's parser-only container.
fn parameter_span(
    parsed: ProcedureHeader<'_>,
    metadata: &ProcedureMetadata,
    index: usize,
) -> Result<dm_codegen_byond::LowerSpan, String> {
    let parameter = metadata
        .signature
        .parameters
        .get(index)
        .ok_or("source helper argument is out of range")?;
    let lexed = dm_syntax::lex(parsed.header);
    if !lexed.diagnostics.is_empty() {
        return Err("invalid source helper signature tokens".into());
    }
    let open = lexed
        .tokens
        .iter()
        .find(|token| token.text == "(")
        .ok_or("source helper signature has no argument list")?;
    let start = open
        .span
        .end
        .checked_add(parameter.relative_span.start)
        .ok_or("source helper parameter offset overflow")?;
    let end = open
        .span
        .end
        .checked_add(parameter.relative_span.end)
        .ok_or("source helper parameter extent overflow")?;
    parsed
        .header
        .get(start..end)
        .ok_or("parameter span differs from captured header")?;
    Ok(dm_codegen_byond::LowerSpan {
        start: parsed
            .header_span
            .start
            .checked_add(start)
            .ok_or("parameter start overflow")?,
        end: parsed
            .header_span
            .start
            .checked_add(end)
            .ok_or("parameter end overflow")?,
    })
}
fn source_offset(
    parsed: ProcedureHeader<'_>,
    metadata: &ProcedureMetadata,
    index: usize,
) -> Result<usize, String> {
    let span = parameter_span(parsed, metadata, index)?;
    let parameter = metadata
        .signature
        .parameters
        .get(index)
        .ok_or("source helper argument is out of range")?;
    let start = span
        .start
        .checked_sub(parsed.header_span.start)
        .ok_or("parameter source start precedes current header")?;
    let end = span
        .end
        .checked_sub(parsed.header_span.start)
        .ok_or("parameter source end precedes current header")?;
    let text = parsed
        .header
        .get(start..end)
        .ok_or("source helper parameter span differs from captured header")?;
    let lexed = dm_syntax::lex(text);
    let mut depth = 0i32;
    let mut in_end = None;
    let mut expression_end = text.len();
    for token in &lexed.tokens {
        match token.text.as_str() {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth -= 1,
            "in" if depth == 0 && in_end.is_none() => in_end = Some(token.span.end),
            "as" | "=" if depth == 0 && in_end.is_some() => {
                expression_end = token.span.start;
                break;
            }
            _ => {}
        }
    }
    let in_end = in_end.ok_or("source helper parameter has no captured in expression")?;
    let expression = text
        .get(in_end..expression_end)
        .ok_or("invalid captured argument source extent")?;
    let leading = expression.len() - expression.trim_start().len();
    let expression = expression.trim();
    let actual = dm_syntax::lex(expression);
    let mut tokens = actual.tokens.iter().filter(|token| {
        !matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        )
    });
    let expected = parameter
        .source_expression
        .as_ref()
        .ok_or("source helper expression missing")?;
    if !actual.diagnostics.is_empty()
        || expected.tokens.iter().any(|expected| {
            tokens.next().is_none_or(|actual| {
                actual.kind != expected.kind || dm_ir::SymbolId::of(&actual.text) != expected.text
            })
        })
        || tokens.next().is_some()
    {
        return Err("source helper expression differs from typed signature".into());
    }
    parsed
        .header_span
        .start
        .checked_add(start)
        .and_then(|offset| offset.checked_add(in_end))
        .and_then(|offset| offset.checked_add(leading))
        .ok_or_else(|| "source helper debug offset overflow".into())
}
struct FixedOrigin;
impl dm_codegen_byond::DebugSourceProvider for FixedOrigin {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, _: usize) -> Result<u32, String> {
        Ok(0)
    }
}
#[derive(Clone, Copy)]
pub struct ProcedureHeader<'a> {
    header: &'a str,
    header_span: dm_syntax::Span,
}
impl<'a> From<&'a Item> for ProcedureHeader<'a> {
    fn from(item: &'a Item) -> Self {
        Self {
            header: &item.header,
            header_span: item.header_span,
        }
    }
}
impl<'a> From<dm_tree::frontend::ItemView<'a>> for ProcedureHeader<'a> {
    fn from(item: dm_tree::frontend::ItemView<'a>) -> Self {
        Self {
            header: item.header(),
            header_span: item.header_span(),
        }
    }
}
pub(crate) struct ParameterDiagnosticSource<'a> {
    header: ProcedureHeader<'a>,
    metadata: &'a ProcedureMetadata,
    symbols: &'a SymbolTable,
}
impl<'a> ParameterDiagnosticSource<'a> {
    pub(crate) fn from_current(
        frontend: &'a ColdFrontend,
        item: &Item,
        metadata: &'a ProcedureMetadata,
        symbols: &'a SymbolTable,
    ) -> Option<Self> {
        let header = frontend.expanded.text.get(item.header_span.range())?;
        // Coordinates may differ for synthetic/normalized/custom headers.
        // Such headers cannot issue this source-only diagnostic authority.
        if header != item.header {
            return None;
        }
        Some(Self {
            header: ProcedureHeader {
                header,
                header_span: item.header_span,
            },
            metadata,
            symbols,
        })
    }
    pub(crate) fn from_archive(
        body: &'a dm_tree::frontend::ArchivedBody<'_>,
        metadata: &'a ProcedureMetadata,
        symbols: &'a SymbolTable,
    ) -> Option<Self> {
        let header = body.header_source()?;
        if header != body.header().header {
            return None;
        }
        Some(Self {
            header: ProcedureHeader {
                header,
                header_span: body.header().header_span,
            },
            metadata,
            symbols,
        })
    }
    pub(crate) fn authenticates(&self, span: &dm_codegen_byond::LowerSpan) -> bool {
        self.metadata
            .signature
            .parameters
            .iter()
            .enumerate()
            .any(|(index, _)| {
                parameter_span(self.header, self.metadata, index)
                    .is_ok_and(|issued| issued.start == span.start && issued.end == span.end)
            })
    }
    pub(crate) fn declaration(
        &self,
        name: &str,
    ) -> Result<Option<dm_codegen_byond::LowerSpan>, String> {
        let index = self
            .metadata
            .signature
            .parameters
            .iter()
            .rposition(|parameter| self.symbols.text(parameter.name) == Some(name));
        index
            .map(|index| parameter_span(self.header, self.metadata, index))
            .transpose()
    }
}
pub struct HelperInputs<'a> {
    pub frontend: &'a ColdFrontend,
    pub parsed: ProcedureHeader<'a>,
    pub metadata: &'a ProcedureMetadata,
    pub owner: UnitIdentity,
    pub inputs: &'a ProcedureInputs,
    pub helpers: &'a [ArgumentSourceHelper],
    pub symbols: &'a SymbolTable,
}
pub fn lower_helpers<R: Resolver>(
    context: HelperInputs<'_>,
    host: &R,
) -> Result<Vec<LoweredHelper>, HelperFailure> {
    let HelperInputs {
        frontend,
        parsed,
        metadata,
        owner,
        inputs,
        helpers,
        symbols,
    } = context;
    let mut result = Vec::with_capacity(helpers.len());
    for helper in helpers {
        if helper.frame_parameters != inputs.parameters {
            return Err("argument source frame differs from owning procedure".into());
        }
        let absolute = source_offset(parsed, metadata, helper.argument)?;
        let raw = frontend
            .expanded
            .text
            .get(parsed.header_span.start..parsed.header_span.end)
            .ok_or("source helper header outside captured expanded source")?;
        if raw != parsed.header {
            return Err("source helper header mapping is not exact".into());
        }
        let origin = frontend
            .location(absolute)
            .ok_or("source helper expression origin missing")?;
        let debug_origins = DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: origin.semantic_path.clone(),
                line: u32::try_from(origin.line).map_err(|_| "source helper line exceeds u32")?,
            }],
        };
        let expression = helper
            .expression
            .source_text(symbols)
            .ok_or("argument source expression spelling unavailable")?;
        // This header is a syntax container only; it is not emitted into any
        // callable procedure inventory or semantic key.
        let container = syntax_container(&expression)?;
        let mut frame = inputs.clone();
        frame.parameter_defaults.clear();
        frame.parameter_value_sources.clear();
        let mut code = visible_formals::compile(
            &container,
            &expression,
            helper.argument,
            metadata,
            &frame,
            symbols,
            host,
        )
        .map_err(|errors| {
            failure::lowered(
                frontend,
                parsed,
                metadata,
                owner,
                absolute,
                &origin,
                &expression,
                errors,
            )
        })?;
        // This executable-only helper does not retain a separate formal frame.
        // Composition binds today's owning parameter-name prefix at emission;
        // Arg operands continue to address the owner's full lexical frame.
        code.procedure.argument_names.clear();
        code.procedure.argument_type_flags.clear();
        code.procedure.argument_value_sources.clear();
        result.push(LoweredHelper {
            owner,
            argument: u32::try_from(helper.argument)
                .map_err(|_| "argument source position exceeds u32")?,
            code,
            debug_origins,
        });
    }
    Ok(result)
}

/// Rebind executable-only cache data to today's issued signature and argument frame.
pub(crate) fn rebase_cached_helper(
    context: HelperInputs<'_>,
    argument: u32,
    code: ResolverProc,
) -> Result<LoweredHelper, String> {
    let helper = context
        .helpers
        .iter()
        .find(|helper| helper.argument == argument as usize)
        .ok_or("cached helper argument not prepared")?;
    if helper.frame_parameters != context.inputs.parameters
        || !code.procedure.argument_names.is_empty()
        || !code.procedure.argument_type_flags.is_empty()
        || !code.procedure.argument_value_sources.is_empty()
    {
        return Err("cached helper frame differs from current preparation".into());
    }
    let debug_origins = current_helper_origin(&context, helper)?;
    Ok(LoweredHelper {
        owner: context.owner,
        argument,
        code,
        debug_origins,
    })
}

/// Validate today's issued header/frame before binding shared frozen helper code.
pub(crate) fn current_helper_origins(
    context: &HelperInputs<'_>,
    argument: u32,
) -> Result<DebugOrigins, String> {
    let helper = context
        .helpers
        .iter()
        .find(|helper| helper.argument == argument as usize)
        .ok_or("cached helper argument not prepared")?;
    if helper.frame_parameters != context.inputs.parameters {
        return Err("cached helper frame differs from current preparation".into());
    }
    current_helper_origin(context, helper)
}
fn current_helper_origin(
    context: &HelperInputs<'_>,
    helper: &ArgumentSourceHelper,
) -> Result<DebugOrigins, String> {
    let absolute = source_offset(context.parsed, context.metadata, helper.argument)?;
    if context
        .frontend
        .expanded
        .text
        .get(context.parsed.header_span.start..context.parsed.header_span.end)
        != Some(context.parsed.header)
    {
        return Err("cached helper header mapping differs".into());
    }
    let origin = context
        .frontend
        .location(absolute)
        .ok_or("cached helper origin unavailable")?;
    Ok(DebugOrigins {
        entries: vec![DebugOrigin {
            semantic_path: origin.semantic_path.clone(),
            line: u32::try_from(origin.line).map_err(|_| "helper line exceeds u32")?,
        }],
    })
}

#[cfg(test)]
mod view_tests {
    use super::*;
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    #[test]
    fn borrowed_current_header_preserves_argument_source_offset_after_shift() {
        for source in [
            "/proc/probe(x in list(1, 2))\n    return x\n",
            "\n\n/proc/probe(x in list(1, 2))\n    return x\n",
        ] {
            let frontend = dm_tree::frontend::build(
                std::path::Path::new("project.dme"),
                &Source(source),
                &Default::default(),
                1,
            )
            .unwrap();
            let body = &frontend.bodies[0];
            let view = frontend.compact_body(body).unwrap();
            let metadata = frontend
                .snapshot
                .tree
                .member(body.member)
                .unwrap()
                .metadata
                .procedure
                .as_ref()
                .unwrap();
            let absolute = source_offset(view.into(), metadata, 0).unwrap();
            assert!(frontend.expanded.text[absolute..].starts_with("list(1, 2)"));
            assert_eq!(frontend.location(absolute).unwrap().line, body.source.line);
            let requested = view.materialize();
            assert_eq!(
                source_offset((&requested).into(), metadata, 0).unwrap(),
                absolute
            );
        }
    }
}

const SYNTAX_PREFIX: &str = "/proc/__argument_source_syntax()\n    return ";
fn syntax_container(expression: &str) -> Result<Item, String> {
    let mut ast = dm_syntax::parse(&format!("{SYNTAX_PREFIX}{expression}\n"));
    if !ast.diagnostics.is_empty() || ast.items.len() != 1 {
        return Err("unsupported argument source expression syntax".into());
    }
    Ok(ast.items.remove(0))
}
