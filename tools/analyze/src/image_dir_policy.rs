//! One registration and message contract for the old and captured ImageDir folds.
use crate::lint::{Meta, Policy, RuleMeta, ScanKind};
use crate::tree::CODE_DM;

pub(crate) const RULE: &str = "dir_after_build";
pub(crate) const MESSAGE: &str = "`.dir` assigned to an image or mutable_appearance after it is built";

const HINT: &str = "a dir assigned to an image or mutable_appearance after it is built is dropped when it becomes an overlay or underlay, whatever the value. \
Build the image with its dir: image(icon, loc, icon_state, layer, dir), image(of, dir = d) or look_overlay_image(..., dir =). A mutable_appearance has no \
dir argument: use an image, or leave the dir to the holder. dq_overlay_dir_renders holds the rule";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::image_dir_after_build::SCOPE_META_0.name,
    group: crate::allow_registry_fields::image_dir_after_build::SCOPE_META_0.group,
    label: "image_dir_after_build",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: RULE, hint: HINT }],
    allow: crate::allow_registry_fields::image_dir_after_build::ALLOW_0,
    lists: crate::allow_registry_fields::image_dir_after_build::SCOPE_META_0.lists,
};
