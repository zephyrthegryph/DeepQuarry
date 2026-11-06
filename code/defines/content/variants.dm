// A reference to one row of a variant family (code/content/variants/README.md): the text of the row's old path.
//
//	VARIANT(/obj/structure/sign/department/medbay)
//
// is "/obj/structure/sign/department/medbay", what the type /obj/structure/sign/department/medbay used to be. It is one constant text
// (nothing is allocated per instance that holds it, and a list or table cannot flatten it into parts): the parent is the path up to the last
// segment, the key is the last segment. The path is not a type any more, so the compiler does not check it; tools/ci/check_variants.py (part of
// check_ratchets.sh) fails on a parent that is no registered family or a key its table does not have. variant_new() makes the thing;
// variant_ref(parent, key) builds the same text from two values.
#define VARIANT(ref) #ref
