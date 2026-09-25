//! `#[vg::events(Pump)]` / `#[vg::events(domain = power)]` on an enum
//! (`rust_architecture.md` §4.8): implements `vg_core::event::Event`, the one
//! typed event codec.
//!
//! - Component events (`#[vg::events(Pump)]`) carry the component's domain
//!   and kind in their header; DM dispatches them to the entity's atom
//!   (`on_pump_starved()`).
//! - Domain events (`#[vg::events(domain = power)]`) are about a region or
//!   the domain as a whole (kind 0); DM dispatches them to a global handler
//!   (`/proc/vg_on_power_brownout(...)`).
//!
//! Variants are unit or carry named numeric fields (`f32`, `f64`, integers,
//! `bool`), encoded in declaration order. An `#[vg(unit = "K")]` on a
//! variant field documents its unit for the generator.

use proc_macro2::TokenStream;
use quote::quote;
use syn::parse::{Parse, ParseStream};
use syn::{Ident, Token};

enum Owner {
    Component(Ident),
    Domain(Ident),
}

impl Parse for Owner {
    fn parse(input: ParseStream) -> syn::Result<Self> {
        let first: Ident = input.parse()?;
        if first == "domain" && input.peek(Token![=]) {
            input.parse::<Token![=]>()?;
            return Ok(Self::Domain(input.parse()?));
        }
        Ok(Self::Component(first))
    }
}

fn snake_case(ident: &Ident) -> String {
    crate::component::snake_case(ident)
}

pub fn expand(
    attr: proc_macro::TokenStream,
    item: proc_macro::TokenStream,
) -> proc_macro::TokenStream {
    let owner = syn::parse_macro_input!(attr as Owner);
    let mut input = syn::parse_macro_input!(item as syn::ItemEnum);
    match expand_inner(&owner, &mut input) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

#[allow(clippy::too_many_lines)]
fn expand_inner(owner: &Owner, input: &mut syn::ItemEnum) -> syn::Result<TokenStream> {
    let enum_ident = input.ident.clone();

    let mut schemas = Vec::new();
    let mut id_arms = Vec::new();
    let mut encode_arms = Vec::new();
    let mut decode_arms = Vec::new();
    let mut names = Vec::new();
    let mut from_id_arms = Vec::new();
    let mut all_unit = true;

    for (i, v) in input.variants.iter_mut().enumerate() {
        let Ok(id) = u8::try_from(i) else {
            return Err(syn::Error::new_spanned(&*v, "at most 256 event variants"));
        };
        let vident = v.ident.clone();
        let name = snake_case(&vident);
        names.push(name.clone());
        match &mut v.fields {
            syn::Fields::Unit => {
                schemas.push(quote! { ::vg_core::event::EventSchema { name: #name, fields: &[] } });
                id_arms.push(quote! { Self::#vident => #id });
                encode_arms.push(quote! { Self::#vident => {} });
                decode_arms
                    .push(quote! { (#id, []) => ::std::option::Option::Some(Self::#vident) });
                from_id_arms.push(quote! { #id => ::std::option::Option::Some(Self::#vident) });
            }
            syn::Fields::Named(named) => {
                all_unit = false;
                let mut field_schemas = Vec::new();
                let mut idents = Vec::new();
                let mut tys = Vec::new();
                for f in &mut named.named {
                    let fid = f.ident.clone().expect("named");
                    let mut unit = quote! { ::std::option::Option::None };
                    let mut kept = Vec::new();
                    for a in f.attrs.drain(..) {
                        if a.path().is_ident("vg") {
                            let kv: syn::MetaNameValue = a.parse_args()?;
                            if !kv.path.is_ident("unit") {
                                return Err(syn::Error::new_spanned(
                                    kv.path,
                                    "expected `unit = \"...\"`",
                                ));
                            }
                            let value = kv.value;
                            unit = quote! { ::std::option::Option::Some(#value) };
                        } else {
                            kept.push(a);
                        }
                    }
                    f.attrs = kept;
                    let fname = fid.to_string();
                    field_schemas.push(
                        quote! { ::vg_core::event::EventField { name: #fname, unit: #unit } },
                    );
                    idents.push(fid);
                    tys.push(f.ty.clone());
                }
                let n = idents.len();
                let slots: Vec<Ident> = (0..n).map(|k| quote::format_ident!("__p{k}")).collect();
                schemas.push(quote! { ::vg_core::event::EventSchema { name: #name, fields: &[#(#field_schemas),*] } });
                id_arms.push(quote! { Self::#vident { .. } => #id });
                encode_arms.push(quote! {
                    Self::#vident { #(#idents),* } => {
                        #(
                            #[allow(clippy::cast_possible_truncation)]
                            out.push(::vg_core::component::FieldValue::to_f64(*#idents) as f32);
                        )*
                    }
                });
                decode_arms.push(quote! {
                    (#id, [#(#slots),*]) => ::std::option::Option::Some(Self::#vident {
                        #(#idents: <#tys as ::vg_core::component::FieldValue>::from_f64(f64::from(*#slots))),*
                    })
                });
            }
            syn::Fields::Unnamed(_) => {
                return Err(syn::Error::new_spanned(
                    &*v,
                    "#[vg::events] variants are unit or have named fields",
                ));
            }
        }
    }

    let (domain_id, kind) = match owner {
        Owner::Component(c) => (
            quote! { <#c as ::vg_core::component::Component>::DOMAIN_ID },
            quote! { <#c as ::vg_core::component::Component>::KIND },
        ),
        Owner::Domain(d) => {
            let d = d.to_string();
            (quote! { ::vg_core::component::domain_id(#d) }, quote! { 0 })
        }
    };

    let derives = if all_unit {
        quote! { #[derive(::std::clone::Clone, ::std::marker::Copy, ::std::fmt::Debug, ::std::cmp::PartialEq, ::std::cmp::Eq)] }
    } else {
        quote! { #[derive(::std::clone::Clone, ::std::fmt::Debug, ::std::cmp::PartialEq)] }
    };
    let n = names.len();
    let unit_helpers = if all_unit {
        quote! {
            /// The variant with numeric id `id`.
            #[must_use]
            pub fn from_id(id: u8) -> ::std::option::Option<Self> {
                match id {
                    #(#from_id_arms,)*
                    _ => ::std::option::Option::None,
                }
            }
        }
    } else {
        quote! {}
    };

    Ok(quote! {
        #derives
        #input

        impl #enum_ident {
            /// `snake_case` names in declaration order (the generated DM
            /// handler is `on_<source>_<name>`).
            pub const NAMES: [&'static str; #n] = [#(#names),*];

            /// The variant's stable numeric id.
            #[must_use]
            pub fn id(&self) -> u8 {
                <Self as ::vg_core::event::Event>::id(self)
            }

            #[must_use]
            pub fn name(&self) -> &'static str {
                Self::NAMES[usize::from(self.id())]
            }

            #unit_helpers
        }

        impl ::vg_core::event::Event for #enum_ident {
            const DOMAIN_ID: u8 = #domain_id;
            const KIND: u16 = #kind;
            const VARIANTS: &'static [::vg_core::event::EventSchema] = &[#(#schemas),*];

            fn id(&self) -> u8 {
                match self {
                    #(#id_arms),*
                }
            }

            #[allow(unused_variables)]
            fn encode(&self, out: &mut ::std::vec::Vec<f32>) {
                match self {
                    #(#encode_arms),*
                }
            }

            fn decode(id: u8, payload: &[f32]) -> ::std::option::Option<Self> {
                match (id, payload) {
                    #(#decode_arms,)*
                    _ => ::std::option::Option::None,
                }
            }
        }
    })
}
