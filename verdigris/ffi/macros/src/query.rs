//! `#[vg::query(Type, name = [fields...], ...)]` (`rust_bindings.md` §3):
//! generates one query method per named group, returning every listed
//! field's value in one call, and the group's field ids. DM reaches a group
//! through the generic `vg_component_get_many(entity, kind, ids)` bind with
//! those ids (the generator emits `pump_query_ui()`); nothing here touches
//! `byondapi`.

use proc_macro2::TokenStream;
use quote::{format_ident, quote};
use syn::parse::{Parse, ParseStream};
use syn::{Ident, Token};

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
    let methods = args.groups.iter().map(|g| {
        let method = format_ident!("query_{}", g.name);
        let names_const = format_ident!("QUERY_{}_FIELDS", g.name.to_string().to_uppercase());
        let ids_fn = format_ident!("query_{}_ids", g.name);
        let n = g.fields.len();
        let names: Vec<String> = g.fields.iter().map(ToString::to_string).collect();
        let values = g.fields.iter().map(|f| quote! { ::vg_core::component::QueryValue::from(self.#f) });
        quote! {
            impl #ty {
                /// Field names of this query group, in call order.
                pub const #names_const: [&'static str; #n] = [#(#names),*];

                /// This group's fields in one call (`rust_bindings.md` §3, §6).
                #[must_use]
                pub fn #method(&self) -> [::vg_core::component::QueryValue; #n] {
                    [#(#values),*]
                }

                /// This group's field ids, for the generic FFI read.
                #[must_use]
                pub fn #ids_fn() -> [::vg_core::component::FieldId; #n] {
                    Self::#names_const.map(|name| {
                        <Self as ::vg_core::component::Component>::field_id(name).expect("query names a declared field")
                    })
                }
            }
        }
    });
    let out: TokenStream = quote! { #(#methods)* };
    out.into()
}
