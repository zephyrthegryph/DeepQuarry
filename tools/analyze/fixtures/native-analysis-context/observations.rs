//! Pure complete observation codec; no expected answers or source authority.
pub fn tokens(text:&str)->Vec<(String,String)>{dm_syntax::lex(text).tokens.into_iter().filter(|token|!matches!(token.kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment)).map(|token|(format!("{:?}",token.kind),token.text)).collect()}
