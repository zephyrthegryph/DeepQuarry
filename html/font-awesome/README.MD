html/font-awesome/ is what a client downloads at join: a stylesheet with only the icons the code names, and the two web fonts cut
down to those glyphs. Do not edit it by hand. It is generated from the full Font Awesome Free files in tools/fontawesome/full/:

    python tools/fontawesome/subset.py          (needs: pip install fonttools brotli)

Run it after adding an icon to the code, to DM data (icon = "user-md") or to a tgui interface, and commit the result.
`python tools/fontawesome/subset.py --check` (also part of tools/ci/check_ratchets.sh) fails when an icon the code names is missing.
An icon name assembled at runtime is invisible to the scan: list it in EXTRA_ICONS in the script.

To update Font Awesome: get the woff2 and all.min.css from https://cdnjs.com/libraries/font-awesome into tools/fontawesome/full/.
browse_rsc can't create subdirectories, so the relative webfont references in all.min.css must be bare file names
(../webfonts/fa-regular-400.woff2 => fa-regular-400.woff2, whatever you call it in the asset datum). Remove the brand and v4 compat css
and `-moz-osx-font-smoothing:grayscale;` from the full file (format it, remove them, minify it); then rerun the script.
