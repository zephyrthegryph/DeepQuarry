//! Request issuer borrows the previous issuer lookup, never its token IDs.
pub(super) struct RequestTokens {
    tokens: crate::initializer_tokens::Tokens,
}
impl RequestTokens {
    pub(super) fn new(debug: bool, previous: Option<&super::token_roster::CurrentRoster>) -> Self {
        Self {
            tokens: crate::initializer_tokens::Tokens::with_previous(
                debug,
                previous.and_then(|previous| previous.canonical_owner()),
            ),
        }
    }
    pub(super) fn share_key(&self, key: std::sync::Arc<[u8]>) -> std::sync::Arc<[u8]> {
        self.tokens.share_key(key)
    }
    pub(super) fn issuer(&mut self) -> &mut crate::initializer_tokens::Tokens {
        &mut self.tokens
    }
}
