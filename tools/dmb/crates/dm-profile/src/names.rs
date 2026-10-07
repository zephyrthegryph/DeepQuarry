//! Preserve dynamic stage labels in Chrome's span names.
use tracing::{
    field::{Field, Visit},
    span::{Attributes, Id},
    Subscriber,
};
use tracing_subscriber::{layer::Context, registry::LookupSpan, Layer};
pub struct StageName(pub String);
pub struct Names;
#[derive(Default)]
struct Fields(Option<String>);
impl Visit for Fields {
    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "stage" {
            self.0 = Some(value.into());
        }
    }
    fn record_debug(&mut self, _field: &Field, _value: &dyn std::fmt::Debug) {}
}
impl<S> Layer<S> for Names
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    fn on_new_span(&self, attributes: &Attributes<'_>, id: &Id, context: Context<'_, S>) {
        let mut fields = Fields::default();
        attributes.record(&mut fields);
        if let (Some(name), Some(span)) = (fields.0, context.span(id)) {
            span.extensions_mut().insert(StageName(name));
        }
    }
}
