# Native modified-resource descriptor controls

BYOND 516.1687; every control compiled alone, hidden, within 60 seconds,
without DreamDaemon. All source, assets, DMB/RSC and logs are SHA-bound in
receipt.json. All five controls compile with zero errors and warnings.

* `aliases`: asset.txt and ./asset.txt plus a class default share tag41
  descriptor0. Initializer67 is PushVal(resource tag12, ID0), then Src.asset
  SetVar437. RSC preserves two names but DMB has one resource identity.
* `same_payload-explicit`: different paths one/asset.txt and two/asset.txt
  have identical bytes. Both modified values share descriptor0 and resource0;
  RSC has two entries. Initializer67 uses resource0.
* `different_payload-explicit`: the paths have distinct bytes. Values use
  descriptors0 and1. Initializer68 uses resource0; initializer67 uses
  resource1. Both use the same Src.asset setter. Descriptor dedup therefore
  follows resolved resource content, not literal spelling or source context.
* `same_payload` and `different_payload`: FILE_DIR one, undef, FILE_DIR two
  both resolve the same literal asset.txt to the first payload. Both share
  descriptor0/resource0 and produce one RSC entry. Even different bytes in
  two/asset.txt do not distinguish these two references in this control.
  These controls do **not** prove that the second search context selected two.

Modified instances are kind9/class0. Default fields use tag41 descriptor
indices, while initializer values use tag12 resource indices. No resource
to text conversion, runtime allocation or lifetime conclusion is established.
