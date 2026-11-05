// A reference to one row of a variant family (code/content/variants/README.md): list(parent type, key).
//
//	VARIANT(/obj/structure/sign/department, "medbay")
//
// is what the type /obj/structure/sign/department/medbay used to be. The type is checked by the compiler; the key is checked by
// tools/ci/check_variants.py (part of check_ratchets.sh), which fails on a key the parent's table does not have. variant_new() makes
// the thing; variant_alias_of() turns an old path's text into the same reference.
#define VARIANT(path, key) list(path, key)
