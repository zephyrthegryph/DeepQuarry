//! Shared INPUT ONLY; every old/native disposition is produced independently.
pub const CASES:&[(&str,&str)]=&[
 ("empty",""),("return_void","    return
"),("return_number","    return 1
"),("return_ident","    return argument
"),("return_simple_binary","    return 1 + 2
"),
 ("missing_binary_operand_number","    return 1 +
"),("missing_binary_operand_ident","    return argument *
"),("missing_group_operand","    return (1 +)
"),("missing_throw_value","    throw
"),("missing_goto_label","    goto
"),
 ("local_var_block","    var
        value = 1
    return value
"),("if_return","    if(argument)
        return 1
    return 2
"),
 ("return_zero_call","    return choose()\n"),("return_zero_call_member","    return choose().field\n"),
 ("set_ident_return_null","    set SpacemanDMM_return_type=argument\n    return null\n"),
 ("set_member_return_null","    set SpacemanDMM_return_type=argument.type\n    return null\n"),
 ("set_index_member_return_null","    set SpacemanDMM_return_type=argument[_].type\n    return null\n"),
 ("set_binary_type_return_null","    set SpacemanDMM_return_type=argument || /datum/a\n    return null\n"),
 ("set_repeated_valid_then_numeric","    set SpacemanDMM_return_type=/datum/b\n    set SpacemanDMM_return_type=1+2\n    return null\n"),
 ("set_only","    set SpacemanDMM_return_type=argument\n"),
 ("set_then_missing_rhs","    set SpacemanDMM_return_type=argument\n    return argument +\n"),
 ("malformed_alphanumeric_number","    return 123abc\n"),("valid_exponent_currently_unissued","    return 1e3\n"),
 ("null_call_unissued","    return null()\n"),("literal_call_unissued","    return 1()\n"),
];
pub fn source(body:&str)->String{format!("/proc/before()
    return 1
/proc/probe(argument)
{body}/proc/after()
    return 2
/datum/later
    var/after_field
")}
