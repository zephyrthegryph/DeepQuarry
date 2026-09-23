//! `#[vg::query(Type, name = [fields...], ...)]` (`rust_bindings.md` §3):
//! generates one query method per named group, returning every listed
//! field's value in one call (`pump_query_ui()`), plus — under
//! `#[cfg(target_arch = "x86")]`, the same host/i686 split
//! `#[vg::component]`'s glue uses (`component.rs`'s module docs) — the FFI
//! proc the generated `pump_query_ui()` DM wrapper calls.

use proc_macro2::TokenStream;
use quote::{format_ident, quote};
use syn::parse::{Parse, ParseStream};
use syn::{Ident, LitStr, Token};

struct Group {
    name: Ident,
    fields: Vec<Ident>,
}

struct QueryArgs {
    ty: Ident,
    groups: Vec<Group>,
}

impl Parse for QueryArgs {
    fn parse(input: ParseStream) -> syn::Result<Self> {
        let ty: Ident = input.parse()?;
        let mut groups = Vec::new();
        while input.peek(Token![,]) {
            input.parse::<Token![,]>()?;
            if input.is_empty() {
                break;
            }
            let name: Ident = input.parse()?;
            input.parse::<Token![=]>()?;
            let content;
            syn::bracketed!(content in input);
            let fields: syn::punctuated::Punctuated<Ident, Token![,]> =
                content.parse_terminated(Ident::parse, Token![,])?;
            groups.push(Group {
                name,
                fields: fields.into_iter().collect(),
            });
        }
        if groups.is_empty() {
            return Err(input.error("#[query] needs at least one `name = [fields...]` group"));
        }
        Ok(Self { ty, groups })
    }
}

pub fn expand(attr: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let args = syn::parse_macro_input!(attr as QueryArgs);
    let ty = &args.ty;
    // The naming-convention contract `#[vg::component]` establishes for its
    // own get/set/bind glue (`component.rs`'s module docs): `__{ty}_with`
    // and `__{ty}_cell_of` are generated, byondapi-gated helpers of that
    // macro's expansion on the same struct, referenced here by the same
    // predictable name rather than passed through explicitly. `snake_case`
    // (shared, not reimplemented here) is what makes the name predictable
    // for a multi-word component too.
    let lower = crate::component::snake_case(ty);
    let with_fn = format_ident!("__{lower}_with");
    let cell_of_fn = format_ident!("__{lower}_cell_of");
    let methods = args.groups.iter().map(|g| {
        let method = format_ident!("query_{}", g.name);
        let names_const = format_ident!("QUERY_{}_FIELDS", g.name.to_string().to_uppercase());
        let n = g.fields.len();
        let names: Vec<String> = g.fields.iter().map(ToString::to_string).collect();
        let values = g.fields.iter().map(|f| quote! { ::vg_core::component::QueryValue::from(self.#f) });
        let ffi_fn = format_ident!("{lower}_query_{}", g.name);
        let ffi_path = LitStr::new(&format!("/proc/{lower}_query_{}", g.name), g.name.span());
        quote! {
            impl #ty {
                /// Field names of this query group, in call order.
                pub const #names_const: [&'static str; #n] = [#(#names),*];

                /// This group's fields in one call (`rust_bindings.md` §3, §6).
                #[must_use]
                pub fn #method(&self) -> [::vg_core::component::QueryValue; #n] {
                    [#(#values),*]
                }
            }

            /// The FFI half of the method above: this group's fields in one
            /// call, as a DM list in declaration order (`rust_architecture.md`
            /// §5). Gated exactly like `#[vg::component]`'s own get/set/bind
            /// glue (see that module's docs) — absent on a host build, so
            /// `#[vg::query]` on a host-tested component never needs
            /// `byondapi` either.
            #[cfg(target_arch = "x86")]
            #[::auxmacros::bind(#ffi_path)]
            fn #ffi_fn(entity: ::byondapi::value::ByondValue) -> ::eyre::Result<::byondapi::value::ByondValue> {
                let cell = #cell_of_fn(&entity)?;
                let v = #with_fn(|w| w.read(cell).ok_or_else(|| ::eyre::eyre!("row {cell} out of range")))?;
                let values = v.#method();
                let items: ::std::vec::Vec<::byondapi::value::ByondValue> = values
                    .iter()
                    .map(|q| match q {
                        ::vg_core::component::QueryValue::F32(x) => ::byondapi::value::ByondValue::from(*x),
                        ::vg_core::component::QueryValue::Bool(b) => {
                            ::byondapi::value::ByondValue::from(if *b { 1.0f32 } else { 0.0f32 })
                        }
                    })
                    .collect();
                let list = ::byondapi::value::ByondValue::new_list()?;
                list.write_list(&items)?;
                ::std::result::Result::Ok(list)
            }
        }
    });
    let out: TokenStream = quote! { #(#methods)* };
    out.into()
}
