//! One native grammar DATA projection of actual produced macro token values.
//! Shared by the genuine condition lender and later final-output owner.
use super::original_literal_owner::static_literal_using;
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroText as Text}};
use dm_syntax::{OriginalLiteralData,OriginalLiteralPool,SettingAdmission,TokenKind};use std::io;
#[derive(Clone,Copy)]pub(super) enum Adjacency{Word,Punct,Other,Whitespace}
/// Canonical separation of already-issued values, shared by final output and
/// completed condition transport. No lexing or punctuation joining is done.
pub(super) fn needs_separator(previous:Option<Adjacency>,next:Adjacency)->bool{matches!((previous,next),(Some(Adjacency::Word),Adjacency::Word)|(Some(Adjacency::Punct),Adjacency::Punct))}
pub(super) struct OriginalNativeProjection<S = Text> {
    pub(super) kind: TokenKind,
    pub(super) spelling: S,
    pub(super) literal: Option<OriginalLiteralData>,
    pub(super) adjacency: Adjacency,
}

enum ActualSpelling<'a> {
    Ident(&'a str),
    Static(&'static str),
    Literal,
    Display,
}

fn actual_spelling<'a>(actual: &'a Token<'_>) -> io::Result<(TokenKind, Adjacency, ActualSpelling<'a>)> {
    Ok(match &actual.value {
        Value::Ident { spelling, .. } => (TokenKind::Ident, Adjacency::Word, ActualSpelling::Ident(spelling.get())),
        Value::Punct(text) => {
            let (kind, adjacency) = match *text {
                "in" => (TokenKind::Ident, Adjacency::Word),
                "\n" => (TokenKind::Newline, Adjacency::Whitespace),
                " " | "\t" => (TokenKind::Whitespace, Adjacency::Whitespace),
                _ => (dm_syntax::original_scalar_transport::original_punctuation_native_kind(text), Adjacency::Punct),
            };
            (kind, adjacency, ActualSpelling::Static(*text))
        }
        Value::Int(_) | Value::Float(_) => (TokenKind::Number, Adjacency::Word, ActualSpelling::Literal),
        Value::String(_) => (TokenKind::String, Adjacency::Other, ActualSpelling::Literal),
        Value::Resource(_) => (TokenKind::Resource, Adjacency::Other, ActualSpelling::Literal),
        Value::DocComment { .. } => (TokenKind::Comment, Adjacency::Other, ActualSpelling::Display),
        Value::InterpBegin(_) | Value::InterpPart(_) | Value::InterpEnd(_) => {
            (TokenKind::Interpolation, Adjacency::Other, ActualSpelling::Literal)
        }
        Value::Eof => return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "actual source End is not an emitted grammar token",
        )),
    })
}

fn write_actual_spelling(
    spelling: ActualSpelling<'_>,
    actual: &Token<'_>,
    literal: Option<&OriginalLiteralData>,
    out: &mut Text,
    a: &SettingAdmission<'_>,
) -> io::Result<()> {
    match spelling {
        ActualSpelling::Ident(text) => out.push_str(text, a),
        ActualSpelling::Static(text) => out.push_str(text, a),
        ActualSpelling::Literal => out.push_str(literal.ok_or(io::ErrorKind::InvalidData)?.raw(), a),
        // Display is the unique exact docs judge only.
        ActualSpelling::Display => actual.write_display(out, a),
    }
}

/// Condition transport still requires an owned Token string. Preserve its
/// acquisition and allocation path.
pub(super) fn project_native_token_using(
    actual: &Token<'_>,
    provider: &dyn SourceProvider,
    a: &SettingAdmission<'_>,
    pool: Option<&mut OriginalLiteralPool>,
) -> io::Result<OriginalNativeProjection> {
    let literal = static_literal_using(actual, provider, a, pool)?;
    let mut spelling = Text::new(a)?;
    let (kind, adjacency, source) = actual_spelling(actual)?;
    write_actual_spelling(source, actual, literal.as_ref(), &mut spelling, a)?;
    Ok(OriginalNativeProjection { kind, spelling, literal, adjacency })
}

/// The final receiver already accepts these exact spelling owners. Only the
/// owned fallback has a separate spelling allocation and a matching lease.
pub(super) enum OutputSpelling {
    Static(&'static str),
    Literal,
    Owned(Text),
}

pub(super) fn project_output_token_using(
    actual: &Token<'_>,
    provider: &dyn SourceProvider,
    a: &SettingAdmission<'_>,
    pool: Option<&mut OriginalLiteralPool>,
) -> io::Result<OriginalNativeProjection<OutputSpelling>> {
    // Includes the physical literal provider loan, even when the typed value
    // is already pooled. This precedes every spelling access, as before.
    let literal = static_literal_using(actual, provider, a, pool)?;
    let (kind, adjacency, source) = actual_spelling(actual)?;
    let spelling = match source {
        ActualSpelling::Static(text) => {
            a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
            OutputSpelling::Static(text)
        }
        ActualSpelling::Literal if literal.is_some() => {
            a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
            OutputSpelling::Literal
        }
        _ => {
            let mut text = Text::new(a)?;
            write_actual_spelling(source, actual, literal.as_ref(), &mut text, a)?;
            OutputSpelling::Owned(text)
        }
    };
    Ok(OriginalNativeProjection { kind, spelling, literal, adjacency })
}
