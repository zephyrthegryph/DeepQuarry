//! Argument-source companions use the owning procedure's lexical argument frame.
//! Their semantic identity is owner+argument, never a fabricated callable name.
use crate::{
    debug_sources::{DebugOrigin, DebugOrigins},
    lowering::UnitIdentity,
};
use dm_codegen_byond::{
    lower_resolver::ResolverProc, procedure_abi::ArgumentSourceHelper, ProcedureInputs,
};
use dm_ir::{ProcedureMetadata, Resolver, SymbolTable};
use dm_syntax::{Item, TokenKind};
use dm_tree::frontend::ColdFrontend;

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
fn source_offset(
    parsed: &Item,
    metadata: &ProcedureMetadata,
    index: usize,
) -> Result<usize, String> {
    let parameter = metadata
        .signature
        .parameters
        .get(index)
        .ok_or("source helper argument is out of range")?;
    let lexed = dm_syntax::lex(&parsed.header);
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
    let tokens: Vec<_> = actual
        .tokens
        .iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect();
    let expected = parameter
        .source_expression
        .as_ref()
        .ok_or("source helper expression missing")?;
    if !actual.diagnostics.is_empty()
        || tokens.len() != expected.tokens.len()
        || tokens
            .iter()
            .zip(expected.tokens.iter())
            .any(|(a, b)| a.kind != b.kind || dm_ir::SymbolId::of(&a.text) != b.text)
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
pub struct HelperInputs<'a> {
    pub frontend: &'a ColdFrontend,
    pub parsed: &'a Item,
    pub metadata: &'a ProcedureMetadata,
    pub owner: UnitIdentity,
    pub inputs: &'a ProcedureInputs,
    pub helpers: &'a [ArgumentSourceHelper],
    pub symbols: &'a SymbolTable,
}
pub fn lower_helpers<R: Resolver>(
    context: HelperInputs<'_>,
    host: &R,
) -> Result<Vec<LoweredHelper>, String> {
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
        let ast = dm_syntax::parse(&format!(
            "/proc/__argument_source_syntax()\n    return {expression}\n"
        ));
        if !ast.diagnostics.is_empty() || ast.items.len() != 1 {
            return Err("unsupported argument source expression syntax".into());
        }
        let mut frame = inputs.clone();
        frame.parameter_defaults.clear();
        frame.parameter_value_sources.clear();
        let mut code = dm_codegen_byond::compile_simple_proc_with_resolver_and_debug(
            &ast.items[0].children,
            &frame,
            symbols,
            host,
            Some(&FixedOrigin),
        )
        .map_err(|errors| format!("argument source lowering failed: {errors:?}"))?;
        // VM argument-source records have an empty formal table, while Arg
        // operands continue to address the owner's original lexical frame.
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
        != Some(context.parsed.header.as_str())
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
