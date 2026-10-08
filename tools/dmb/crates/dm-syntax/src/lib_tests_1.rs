use super::*;

#[test]
fn inline_class_fields_do_not_define_a_procedure() {
    let source = "/datum/admin_verb/player_panel_new { name=\"Panel\"; description=\"Open\"; category=\"Admin\"; permissions=(((1<<18)-1)); verb_path=/client/proc/player_panel; enabled=1; }\n";
    assert_eq!(classify(source.trim(), true), ItemKind::Type);
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items[0].kind, ItemKind::Type);
    assert_eq!(ast.items[0].header, "/datum/admin_verb/player_panel_new");
    assert_eq!(ast.items[0].children.len(), 6);
}

#[test]
fn implicit_inline_proc_defaults_are_not_absolute_assignments() {
    let ast = parse("/turf/floor/update_graphic(list/add = null, text/value = \"a=b\") return 0\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items[0].kind, ItemKind::Proc);
    assert_eq!(
        ast.items[0].header,
        "/turf/floor/update_graphic(list/add = null, text/value = \"a=b\")"
    );
    assert_eq!(ast.items[0].children[0].header, "return 0");
    assert_eq!(
        top_level_assignment_index("/datum/name = \"a=b\""),
        Some(12)
    );
    assert_eq!(
        top_level_assignment_index("/datum/proc/run(x = \"a=b\")"),
        None
    );
}

#[test]
fn absolute_assignment_is_not_a_type_declaration() {
    let ast = parse("/datum/language/human/syllables = list(\n    \"one\", \"two\"\n)\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items[0].kind, ItemKind::Statement);
}

#[test]
fn inline_proc_body_is_separate_from_signature() {
    let source = "/proc/rustg_get_version() return call_ext((__rust_g || __detect_rust_g()), \"get_version\")()\n/proc/next()\n    return 1\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items[0].kind, ItemKind::Proc);
    assert_eq!(ast.items[0].header, "/proc/rustg_get_version()");
    assert_eq!(ast.items[0].children.len(), 1);
    assert_eq!(
        ast.items[0].children[0].header,
        "return call_ext((__rust_g || __detect_rust_g()), \"get_version\")()"
    );
    assert_eq!(ast.items[1].header, "/proc/next()");
}

#[test]
fn lex_is_lossless_and_spans_are_bytes() {
    let src = "/obj/é\n  var/icon = 'a.dmi' // test\n";
    let result = lex(src);
    assert_eq!(
        result
            .tokens
            .iter()
            .map(|t| t.text.as_str())
            .collect::<String>(),
        src
    );
    assert!(result.tokens.iter().all(|t| src[t.span.range()] == t.text));
    assert!(result.tokens.iter().any(|t| t.kind == TokenKind::Resource));
}

#[test]
fn parse_nested_declarations_and_reopening_order() {
    let src = "/obj\n  var/name = \"first\"\n  proc/test(x)\n    return x\n/obj\n  var/name = \"second\"\n";
    let ast = parse(src);
    assert_eq!(ast.items.len(), 2);
    assert_eq!(ast.items[0].kind, ItemKind::Type);
    assert_eq!(ast.items[0].children[0].kind, ItemKind::Var);
    assert_eq!(ast.items[0].children[1].kind, ItemKind::Proc);
    assert_eq!(
        ast.items[0].children[1].children[0].kind,
        ItemKind::Statement
    );
    assert!(ast.diagnostics.is_empty());
}

#[test]
fn multiline_proc_signature_and_list_expression_are_one_header_each() {
    let source = "/proc/send_announcement(\n    text,\n    title = \"A (title)\",\n)\n    var/list/colors = list(\n        1,\n        2,\n    )\n    return colors\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 1);
    assert_eq!(ast.items[0].kind, ItemKind::Proc);
    assert!(ast.items[0].header.contains("title ="));
    assert_eq!(ast.items[0].children.len(), 2);
    assert!(ast.items[0].children[0].header.contains("2,"));
}

#[test]
fn braces_and_semicolons_create_nested_statements() {
    let source = "/proc/test() { var/x = 1; if(x) { foo(); bar(); } return x; }\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 1);
    let proc = &ast.items[0];
    assert_eq!(proc.kind, ItemKind::Proc);
    assert_eq!(proc.children.len(), 3);
    assert_eq!(proc.children[1].header, "if(x)");
    assert_eq!(proc.children[1].children.len(), 2);
    let body = parse_proc_body(proc);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert_eq!(body.statements.len(), 3);
}

#[test]
fn inline_proc_with_multiline_list_keeps_call_together() {
    let source = "/datum/globals/var/list/x; /datum/globals/proc/InitX(){x =list(\n NORTHEAST,\n NORTHWEST\n); order += \"x\";}\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 2, "{:?}", ast.items);
    let proc = &ast.items[1];
    assert_eq!(proc.kind, ItemKind::Proc);
    assert_eq!(proc.children.len(), 2, "{:?}", proc.children);
    assert!(proc.children[0].header.contains("NORTHWEST"));
    let body = parse_proc_body(proc);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
}

#[test]
fn macro_generated_inline_proc_with_tabbed_multiline_list() {
    let source = "/datum/controller/global_vars/var/global/list/gzn_check; /datum/controller/global_vars/proc/InitGlobalgzn_check(){gzn_check =list(\n\tNORTH,\n\tSOUTH\n);\tgvars_datum_init_order += \"gzn_check\";}\n/datum/controller/global_vars/var/global/list/csrfz_check; /datum/controller/global_vars/proc/InitGlobalcsrfz_check(){csrfz_check =list(\n\tNORTHEAST,\n\tNORTHWEST,\n\t(NORTH|UP),\n\t(SOUTH|DOWN)\n);\tgvars_datum_init_order += \"csrfz_check\";}\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let proc = &ast.items[3];
    assert_eq!(proc.children.len(), 2, "{:?}", proc.children);
    let body = parse_proc_body(proc);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
}

#[test]
fn include_footprint_before_absolute_path_does_not_attach_to_previous_proc() {
    let source = "/datum/globals/proc/init(){x = list(\nNORTH\n); order += 1;}\n\n                                        /var/__verdigris\n/proc/detect()\n    return 1\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 3, "{:?}", ast.items);
    assert_eq!(ast.items[0].children.len(), 2);
    assert_eq!(ast.items[1].kind, ItemKind::Var);
    assert_eq!(ast.items[1].indent, 0);
}

#[test]
fn object_initializer_braces_do_not_create_statement_blocks() {
    let source = "/proc/planes()\n    . += new /atom/movable/screen/plane_master{plane = 11}\n    . += new /atom/movable/screen/plane_master{plane = 15; name = \"light\"}\n    return .\n";
    let ast = parse(source);
    let proc = &ast.items[0];
    assert_eq!(proc.children.len(), 3, "{:?}", proc.children);
    assert!(proc.children.iter().all(|item| item.children.is_empty()));
    let body = parse_proc_body(proc);
    assert!(body
        .diagnostics
        .iter()
        .all(|d| d.message != "unsupported statement block"));
}

#[test]
fn returned_modified_type_keeps_its_field_expression_in_the_body() {
    let ast = parse("/proc/p()\n    return (/obj/base{a=1;a=2;b=list(/obj/base)})\n");
    let body = &ast.items[0].children;
    assert_eq!(body.len(), 1, "{body:?}");
    assert!(body[0].children.is_empty());
    let parsed = parse_expression(body[0].header.strip_prefix("return ").unwrap());
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let ExprKind::Group(value) = parsed.expr.unwrap().kind else {
        panic!("expected grouped native expression");
    };
    let ExprKind::ObjectInitializer { fields, .. } = value.kind else {
        panic!("return lost its modified-type expression");
    };
    assert_eq!(
        fields
            .iter()
            .map(|(name, _)| name.as_str())
            .collect::<Vec<_>>(),
        ["a", "a", "b"]
    );
}

#[test]
fn object_initializer_expression_preserves_field_overrides() {
    let parsed = parse_expression("new /datum/object_probe{value = 11; name = \"probe\"}");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let expr = parsed.expr.unwrap();
    let ExprKind::Unary { op, value } = expr.kind else {
        panic!("expected new expression");
    };
    assert_eq!(op, "new");
    let ExprKind::ObjectInitializer { object, fields } = value.kind else {
        panic!("expected object initializer");
    };
    assert!(matches!(object.kind, ExprKind::TypePath(ref path) if path == "/datum/object_probe"));
    assert_eq!(fields.len(), 2);
    assert_eq!(fields[0].0, "value");
    assert_eq!(fields[1].0, "name");
}
#[test]
fn native_invalid_return_blocks_stop_before_skeleton_compaction() {
    for source in [
        include_str!("../../../fixtures/phase1/native_modified_returns/bare/probe.dme"),
        include_str!("../../../fixtures/phase1/native_modified_returns/outer_visible/probe.dme"),
    ] {
        for parsed in [
            parse_with_body_mode(source, false),
            parse_declaration_skeleton(source),
        ] {
            assert!(parsed
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == DiagnosticKind::Unsupported
                    && diagnostic.message == RETURN_BLOCK_UNSUPPORTED));
        }
        fn find(items: &[Item]) -> Option<&Item> {
            for item in items {
                if item.header.starts_with("return ") {
                    return Some(item);
                }
                if let Some(found) = find(&item.children) {
                    return Some(found);
                }
            }
            None
        }
        let ast = parse(source);
        let item = find(&ast.items).unwrap();
        assert_eq!(item.children.len(), 1);
        assert_eq!(item.children[0].header, "amount=1");
        let typed = parse_body_items(std::slice::from_ref(item));
        assert!(typed
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.message == RETURN_BLOCK_UNSUPPORTED));
    }
    let grouped =
        include_str!("../../../fixtures/phase1/native_modified_returns/grouped/probe.dme");
    assert!(parse(grouped).diagnostics.is_empty());
    assert!(parse_declaration_skeleton(grouped).diagnostics.is_empty());
}

#[test]
fn dynamic_colon_member_parses_inside_initial_call() {
    let parsed = parse_expression("initial(recipe.result:name)");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let ExprKind::Call { args, .. } = parsed.expr.unwrap().kind else {
        panic!("expected call");
    };
    assert!(
        matches!(&args[0].kind, ExprKind::Member { selector, via_colon: true, .. } if selector == "name")
    );
}

#[test]
fn dynamic_colon_members_parse_in_ternary_branches() {
    for source in [
        "ismob(target) ? target:client : null",
        "recipe ? initial(recipe.result:name) : null",
    ] {
        let parsed = parse_expression(source);
        assert!(
            parsed.diagnostics.is_empty(),
            "{source}: {:?}",
            parsed.diagnostics
        );
        assert!(matches!(
            parsed.expr.unwrap().kind,
            ExprKind::Conditional { .. }
        ));
    }
}

#[test]
fn inline_if_do_macro_braces_preserve_do_while_pairing() {
    let source = "/proc/test()\n    if(length(protected_jobs))\tdo { if(!restricted_jobs) { restricted_jobs = list(); } restricted_jobs |= protected_jobs; } while(0)\n    return 1\n";
    let ast = parse(source);
    let proc = &ast.items[0];
    assert_eq!(proc.children[0].header, "if(length(protected_jobs))");
    assert_eq!(proc.children[0].children[0].header, "do");
    assert_eq!(proc.children[0].children[1].header, "while(0)");
    assert_eq!(proc.children[1].header, "return 1");
    let body = parse_proc_body(proc);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
}

#[test]
fn bare_relative_type_declaration_without_children() {
    let ast = parse("/mob/living/simple_mob/humanoid/clown\n\tclown\n\tname = \"Clown\"\n");
    assert!(ast.diagnostics.is_empty());
    assert_eq!(ast.items[0].children[0].kind, ItemKind::Type);
    assert_eq!(ast.items[0].children[0].header, "clown");
    assert_eq!(ast.items[0].children[1].kind, ItemKind::Statement);
}

#[test]
fn call_valued_override_is_not_implicit_proc() {
    let ast = parse(
        "/datum/example\n    items = list(1, 2)\n    New(value = list())\n        return ..()\n",
    );
    assert!(ast.diagnostics.is_empty());
    assert_eq!(ast.items[0].children[0].kind, ItemKind::Statement);
    assert_eq!(ast.items[0].children[1].kind, ItemKind::Proc);
}

#[test]
fn proc_paths_inside_assignment_values_do_not_declare_procedures() {
    let ast = parse("/datum/interaction/example\n    requires = list(/proc/check, /verb/inspect, /var/flag)\n    /datum/interaction/example/proc/check(value = /proc/fallback)\n        return value\n");
    assert!(ast.diagnostics.is_empty());
    assert_eq!(ast.items[0].children[0].kind, ItemKind::Statement);
    assert_eq!(ast.items[1].kind, ItemKind::Proc);
}

#[test]
fn nameof_dot_proc_path_is_one_type_path_expression() {
    let parsed = parse_expression("nameof(/datum.proc/find_references)");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let Some(Expr {
        kind: ExprKind::Call { args, .. },
        ..
    }) = parsed.expr
    else {
        panic!("expected nameof call");
    };
    assert_eq!(args.len(), 1);
    assert!(
        matches!(&args[0].kind, ExprKind::TypePath(path) if path == "/datum.proc/find_references")
    );
}

#[test]
fn type_path_stops_before_spaced_in_operator() {
    let parsed = parse_expression("pick(/turf in orange(6))");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let Some(Expr {
        kind: ExprKind::Call { args, .. },
        ..
    }) = parsed.expr
    else {
        panic!("expected pick call");
    };
    let [Expr {
        kind: ExprKind::Binary { op, lhs, rhs },
        ..
    }] = args.as_slice()
    else {
        panic!("expected membership argument: {args:?}");
    };
    assert_eq!(op, "in");
    assert!(matches!(&lhs.kind, ExprKind::TypePath(path) if path == "/turf"));
    assert!(
        matches!(&rhs.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if name == "orange"))
    );
    let path = parse_expression("/datum.proc/find_references");
    assert!(path.diagnostics.is_empty());
    assert!(
        matches!(path.expr.unwrap().kind, ExprKind::TypePath(path) if path == "/datum.proc/find_references")
    );
}

#[test]
fn trailing_type_slash_is_canonical_in_values_and_constructors() {
    let path = parse_expression("/obj/trailing_probe/");
    assert!(path.diagnostics.is_empty());
    assert!(
        matches!(path.expr.unwrap().kind, ExprKind::TypePath(path) if path == "/obj/trailing_probe")
    );
    let new = parse_expression("new /obj/trailing_probe/()");
    assert!(new.diagnostics.is_empty(), "{:?}", new.diagnostics);
    let Some(Expr {
        kind: ExprKind::Unary { op, value },
        ..
    }) = new.expr
    else {
        panic!("expected new expression");
    };
    assert_eq!(op, "new");
    assert!(
        matches!(&value.kind, ExprKind::Call { callee, args } if args.is_empty() && matches!(&callee.kind, ExprKind::TypePath(path) if path == "/obj/trailing_probe"))
    );
}

#[test]
fn semicolons_inside_for_control_are_not_split() {
    let source = "/proc/test() { for(var/i = 0; i < 3; i++) { tick(); } }\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items[0].children.len(), 1);
    assert!(ast.items[0].children[0].header.starts_with("for("));
    assert_eq!(ast.items[0].children[0].children.len(), 1);
}

#[test]
fn lexer_reports_unterminated_resource() {
    assert_eq!(lex("'x.dmi").diagnostics.len(), 1);
}

#[test]
fn expressions_preserve_precedence_and_calls() {
    let parsed = parse_expression("foo(2 + 3 * 4, src.name)");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let ExprKind::Call { args, .. } = parsed.expr.unwrap().kind else {
        panic!("expected call")
    };
    assert_eq!(args.len(), 2);
    let ExprKind::Binary { op, rhs, .. } = &args[0].kind else {
        panic!("expected binary")
    };
    assert_eq!(op, "+");
    assert!(matches!(rhs.kind, ExprKind::Binary { ref op, .. } if op == "*"));
    assert!(matches!(args[1].kind, ExprKind::Member { .. }));
}

#[test]
fn expression_parses_nested_ternary() {
    let parsed = parse_expression("foo ? bar : baz");
    assert!(parsed.diagnostics.is_empty());
    assert!(matches!(
        parsed.expr.unwrap().kind,
        ExprKind::Conditional { .. }
    ));
    let nested = parse_expression("foo ? 1 : bar ? 2 : 3");
    assert!(nested.diagnostics.is_empty());
    assert!(matches!(
        nested.expr.unwrap().kind,
        ExprKind::Conditional { .. }
    ));
}

#[test]
fn procedure_body_calls_and_locals_are_statements() {
    let ast = parse("/obj/proc/test()\n    var/x = 1\n    helper()\n    if(x)\n        proc_name()\n/obj/proc/next()\n    return 2\n");
    assert_eq!(ast.items.len(), 2);
    assert_eq!(ast.items[0].kind, ItemKind::Proc);
    assert!(ast.items[0]
        .children
        .iter()
        .all(|item| item.kind == ItemKind::Statement));
    assert_eq!(
        ast.items[0].children[2].children[0].kind,
        ItemKind::Statement
    );
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
}

#[test]
fn multiline_comments_do_not_create_declarations() {
    let ast = parse("/*\n/obj/imaginary\n*/\n/obj/real // trailing\n    var/name = \"real\"\n");
    assert_eq!(ast.items.len(), 1);
    assert_eq!(ast.items[0].header, "/obj/real");
    assert_eq!(ast.items[0].children[0].kind, ItemKind::Var);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
}

#[test]
fn inherited_calls_membership_and_assignments() {
    for source in [
        "..()",
        "x in items",
        "x += 2",
        "new /obj/item(1)",
        "new(user, src)",
        "new",
    ] {
        let parsed = parse_expression(source);
        assert!(
            parsed.diagnostics.is_empty(),
            "{source}: {:?}",
            parsed.diagnostics
        );
        assert!(parsed.expr.is_some(), "{source}");
    }
    let inherited = parse_expression("..()").expr.unwrap();
    assert!(
        matches!(inherited.kind, ExprKind::Call { callee, .. } if matches!(callee.kind, ExprKind::Ident(ref name) if name == ".."))
    );
}

#[test]
fn raw_regex_string_is_one_literal_token() {
    let parsed = parse_expression("@\"^\\w+$\"");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    assert!(matches!(
        parsed.expr.unwrap().kind,
        ExprKind::Literal(value) if value == "@\"^\\w+$\""
    ));
}

#[test]
fn raw_quote_after_backslash_ends_string() {
    let source = r#"@"\" + 1"#;
    let tokens = lex_spans(source);
    assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
    let literals = tokens
        .tokens
        .iter()
        .filter(|token| token.kind == TokenKind::String)
        .map(|token| token.text(source))
        .collect::<Vec<_>>();
    assert_eq!(literals, [r#"@"\""#]);
    let parsed = parse_expression(source);
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
}

#[test]
fn raw_regex_brackets_do_not_consume_following_declarations() {
    let literal = r#"@"^(\d+:\d+|\[0x[0-9a-fA-F]+\](#\d+)?|@\w+)$""#;
    let source = format!("/proc/om_is_handle(h)\n    var/static/regex/shape = regex({literal})\n    return shape\n/mob/dview\n    anchored = 1\n/atom/movable\n    var/anchored = 0\n");
    let tokens = lex_spans(&source);
    assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
    let strings = tokens
        .tokens
        .iter()
        .filter(|token| token.kind == TokenKind::String)
        .map(|token| token.text(&source))
        .collect::<Vec<_>>();
    assert_eq!(strings, [literal]);
    let ast = parse(&source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 3);
    assert_eq!(ast.items[1].header, "/mob/dview");
    assert_eq!(ast.items[2].children[0].header, "var/anchored = 0");
    let unmatched = parse_expression(r#"@"[unclosed""#);
    assert!(
        unmatched.diagnostics.is_empty(),
        "{:?}",
        unmatched.diagnostics
    );
}

#[test]
fn nested_block_comments_hide_inner_closer() {
    let source = "/* outer\n  /* inner */\n  /obj/hidden\n*/\n/obj/real\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 1);
    assert_eq!(ast.items[0].header, "/obj/real");
}

#[test]
fn byond_infinity_is_one_numeric_literal() {
    let source = "1.#INF";
    let tokens = lex_spans(source);
    assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
    assert_eq!(tokens.tokens.len(), 1);
    assert_eq!(tokens.tokens[0].kind, TokenKind::Number);
    let parsed = parse_expression(source);
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    assert!(matches!(parsed.expr.unwrap().kind, ExprKind::Literal(value) if value == source));
}

#[test]
fn exponent_is_left_associative_and_binds_tighter_than_multiply() {
    let parsed = parse_expression("2 * 3 ** 2 ** 1");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let ExprKind::Binary { op, rhs, .. } = parsed.expr.unwrap().kind else {
        panic!("expected multiplication")
    };
    assert_eq!(op, "*");
    let ExprKind::Binary { op, lhs, .. } = rhs.kind else {
        panic!("expected exponent")
    };
    assert_eq!(op, "**");
    assert!(matches!(lhs.kind, ExprKind::Binary { op, .. } if op == "**"));
}

#[test]
fn native_prefix_operators_bind_before_exponentiation() {
    // BYOND516.1687 native_sdk_macros precedence receipt: -2**2=4, !0**0=1.
    for source in ["-2**2", "!0**0", "~2**2"] {
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty());
        let ExprKind::Binary { op, lhs, .. } = parsed.expr.unwrap().kind else {
            panic!("expected outer exponent: {source}")
        };
        assert_eq!(op, "**");
        assert!(matches!(lhs.kind, ExprKind::Unary { .. }), "{source}");
    }
}

#[test]
fn safe_navigation_parses_distinctly() {
    let member = parse_expression("item?.name");
    assert!(member.diagnostics.is_empty(), "{:?}", member.diagnostics);
    assert!(matches!(
        member.expr.unwrap().kind,
        ExprKind::SafeMember { .. }
    ));
    let index = parse_expression("items?[1]");
    assert!(index.diagnostics.is_empty(), "{:?}", index.diagnostics);
    assert!(matches!(
        index.expr.unwrap().kind,
        ExprKind::SafeIndex { .. }
    ));
}

#[test]
fn trailing_comma_in_call_and_constructor_is_accepted() {
    for source in ["list(1, 2,)", "new /datum/x(1, 2,)"] {
        let parsed = parse_expression(source);
        assert!(
            parsed.diagnostics.is_empty(),
            "{source}: {:?}",
            parsed.diagnostics
        );
        assert!(parsed.expr.is_some());
    }
}

#[test]
fn prefix_and_postfix_increment_parse_distinctly() {
    for (source, expected) in [
        ("i++", "post++"),
        ("i--", "post--"),
        ("++i", "pre++"),
        ("--i", "pre--"),
        ("items[index]++", "post++"),
    ] {
        let parsed = parse_expression(source);
        assert!(
            parsed.diagnostics.is_empty(),
            "{source}: {:?}",
            parsed.diagnostics
        );
        assert!(matches!(parsed.expr.unwrap().kind, ExprKind::Unary { op, .. } if op == expected));
    }
    let separated = parse_expression("i + +j");
    assert!(matches!(
        separated.expr.unwrap().kind,
        ExprKind::Binary { .. }
    ));
}

#[test]
fn proc_ref_nameof_nested_constructor_parses() {
    let parsed = parse_expression("_addtimer(new /datum/callback(src, (nameof(.proc/standard_reboot))), report_delay + extra_delay, file=__FILE__, line=__LINE__)");
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    assert!(parsed.expr.is_some());
}
