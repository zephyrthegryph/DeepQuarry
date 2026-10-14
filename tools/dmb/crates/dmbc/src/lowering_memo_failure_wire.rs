use super::*;
#[derive(Serialize, Deserialize)]
pub(super) struct ErrorWire<'a> {
    #[serde(borrow)]
    pub(super) statement: Cow<'a, str>,
    #[serde(borrow)]
    pub(super) reason: Cow<'a, str>,
    pub(super) primary_anchor: Option<dm_codegen_byond::DiagnosticAnchor>,
    pub(super) span: Option<dm_codegen_byond::LowerSpan>,
    pub(super) kind: dm_codegen_byond::LowerErrorKind,
    pub(super) related: Vec<dm_codegen_byond::LowerRelated>,
}
impl<'a> ErrorWire<'a> {
    pub(super) fn capture(error: &'a dm_codegen_byond::LowerError) -> Self {
        Self {
            statement: Cow::Borrowed(&error.statement),
            reason: Cow::Borrowed(&error.reason),
            span: error.span,
            primary_anchor: error.primary_anchor,
            kind: error.kind,
            related: error.related.clone(),
        }
    }
    pub(super) fn rehydrate(self) -> dm_codegen_byond::LowerError {
        dm_codegen_byond::LowerError {
            primary_anchor: self.primary_anchor,
            related: self.related,
            statement: self.statement.into_owned(),
            reason: self.reason.into_owned(),
            span: self.span,
            kind: self.kind,
        }
    }
}
#[derive(Serialize, Deserialize)]
pub(super) struct FailurePayload<'a> {
    #[serde(borrow)]
    pub(super) key: Cow<'a, [u8]>,
    pub(super) identity: Option<ProcedureIdentity>,
    #[serde(borrow)]
    pub(super) reads: Vec<ReadWire<'a>>,
    pub(super) versions: Vec<(dm_ir::ReadDomain, u128)>,
    #[serde(borrow)]
    pub(super) errors: Vec<ErrorWire<'a>>,
}
