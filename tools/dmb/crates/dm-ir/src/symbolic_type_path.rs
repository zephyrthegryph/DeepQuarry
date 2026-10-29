//! Type-path projection over compiler-issued declaration tokens. No DM parse.
use crate::{SymbolTable, SymbolicExpression};
use dm_syntax::TokenKind;
impl SymbolicExpression {
    /// Exactly one absolute type path, excluding groups, unions, calls, prefab
    /// modifications and arithmetic. Token spellings come from the existing
    /// native dictionary; no tokenization, body parse or model is constructed.
    pub fn absolute_type_path(&self, symbols: &SymbolTable) -> Option<String> {
        if self.tokens.is_empty() { return None; }
        // Preserve source_text's token-shape admission without reconstructing
        // or reparsing text: malformed offsets are not compiler type facts.
        let mut previous_end=None;
        for token in self.tokens.iter() {
            let spelling=symbols.text(token.text)?;
            if spelling.len()!=token.relative_span.end.checked_sub(token.relative_span.start)?
                || previous_end.is_some_and(|end|end!=token.relative_span.start) {return None;}
            previous_end=Some(token.relative_span.end);
        }
        if symbols.text(self.tokens[0].text)?!="/" {return None;}
        let mut path=String::from("/");let mut index=1;
        while let Some(token)=self.tokens.get(index) {
            let text=symbols.text(token.text)?;
            if token.kind==TokenKind::Ident || text=="/" {path.push_str(text);index+=1;}
            else if text=="." && self.tokens.get(index+1).and_then(|t|symbols.text(t.text))
                .is_some_and(|s|matches!(s,"proc"|"verb"|"var"))
                && self.tokens.get(index+2).and_then(|t|symbols.text(t.text))==Some("/") {
                path.push('.');path.push_str(symbols.text(self.tokens[index+1].text)?);index+=2;
            } else {return None;}
        }
        if path=="/" {None} else {Some(path.trim_end_matches('/').to_owned())}
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ExpressionToken,SymbolTable};
    fn expression(source:&str,symbols:&mut SymbolTable)->SymbolicExpression {
        SymbolicExpression {tokens:dm_syntax::lex(source).tokens.into_iter()
            .filter(|t|!matches!(t.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment))
            .map(|t|ExpressionToken{kind:t.kind,text:symbols.intern(&t.text).unwrap(),relative_span:t.span}).collect()}
    }
    #[test]
    fn token_projection_matches_valid_primary_parser_return_path_contract() {
        for source in ["/datum/message"," /datum / message ","/list/datum/message","/datum/*comment*/ /message",
                       "/datum/","/obj/.proc/probe",
                       "(/datum/message)","/datum/message()","/datum/message{a=1}","/datum/message|/obj",
                       "datum/message","num","/datum/message + 1","/datum/1","/","/datum.message"] {
            let mut symbols=SymbolTable::default();let value=expression(source,&mut symbols);
            // Independent OLD runtime path: reconstruct symbolic declaration
            // spelling then ask the primary parser, as lower_resolver did.
            let text=value.source_text(&symbols).unwrap();let trimmed=text.trim();
            let old=if trimmed.starts_with('/')&&!trimmed.contains('|') {
                let parsed=dm_syntax::parse_expression(trimmed);
                if parsed.diagnostics.is_empty() {parsed.expr.and_then(|expr|match expr.kind {
                    dm_syntax::ExprKind::TypePath(path)=>Some(path),_=>None})} else {None}
            }else{None};
            assert_eq!(value.absolute_type_path(&symbols),old,"{source}");
        }
    }
    #[test]
    fn malformed_native_token_coordinates_do_not_gain_a_return_type() {
        let mut symbols=SymbolTable::default();let mut value=expression("/datum/item",&mut symbols);
        std::sync::Arc::make_mut(&mut value.tokens)[1].relative_span.end+=1;
        assert!(value.source_text(&symbols).is_none());
        assert!(value.absolute_type_path(&symbols).is_none());
    }
}
