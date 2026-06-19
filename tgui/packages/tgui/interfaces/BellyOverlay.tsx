import { useBackend } from '../backend';

type Layer = {
  url: string;
  color: string;
  alpha: number;
  pixelY?: number;
};

type Data = {
  visible: boolean;
  layers?: Layer[];
};

// BYOND pixel_y values are computed against a 960-tall fullscreen image.
// We scale to the overlay's actual height with translateY in % of the image
// space (negative pixel_y moves down per BYOND convention; mirror that).
const BYOND_FULLSCREEN_PX = 960;

// Validate the backend-supplied icon URL before interpolating it into a CSS
// url(...) context. Only allow same-origin asset paths and data: URIs so a
// malicious value can't smuggle in `javascript:` or break out of url().
const isSafeUrl = (url: string): boolean => {
  if (typeof url !== 'string') return false;
  // Reject anything containing characters that could close the url()/style.
  if (/["'()\\]|\s/.test(url)) return false;
  return (
    /^data:image\/[a-z0-9.+-]+;base64,[a-z0-9+/=]+$/i.test(url) ||
    /^[a-z0-9._\-/?&=%]+$/i.test(url)
  );
};

// Validate the backend-supplied tint before using it as backgroundColor.
const isSafeColor = (color: string): boolean =>
  typeof color === 'string' &&
  /^(#(?:[0-9a-f]{3}|[0-9a-f]{6})|[a-z]+)$/i.test(color.trim());

// Each layer paints the icon's RGB content tinted by L.color, mirroring
// BYOND's `color = "#xxx"` semantic on an /image overlay: per-pixel multiply
// against the tint, alpha preserved.
//
// Two CSS effects combined:
//   1. background: url(icon) over a solid tint, blend-mode multiply.
//      Multiplies the icon's RGB by the tint where the icon is opaque,
//      but leaves the solid tint visible where the icon is transparent.
//   2. mask-image: url(icon) with mask-mode: alpha. Clips the entire layer
//      to the icon's alpha shape, dropping the unwanted solid tint.
//
// The icon URL points to a pre-built animated WebP or still PNG (built by
// tools/build_belly_apngs/build.py). For animated WebPs the browser plays
// the animation natively — no JS animation logic on our side.
const layerStyle = (L: Layer): React.CSSProperties => {
  const pct = ((L.pixelY ?? 0) / BYOND_FULLSCREEN_PX) * 100;
  const safeUrl = isSafeUrl(L.url) ? L.url : '';
  const safeColor = isSafeColor(L.color) ? L.color : undefined;
  const urlValue = safeUrl ? `url(${safeUrl})` : undefined;
  return {
    position: 'fixed',
    inset: 0,
    width: '100%',
    height: '100%',
    backgroundImage: urlValue,
    backgroundSize: '100% 100%',
    backgroundRepeat: 'no-repeat',
    backgroundColor: safeColor,
    backgroundBlendMode: 'multiply',
    WebkitMaskImage: urlValue,
    maskImage: urlValue,
    WebkitMaskRepeat: 'no-repeat',
    maskRepeat: 'no-repeat',
    WebkitMaskSize: '100% 100%',
    maskSize: '100% 100%',
    // WebkitMaskMode isn't typed on React.CSSProperties; use only the standardized maskMode.
    maskMode: 'alpha',
    opacity: L.alpha / 255,
    transform: pct ? `translateY(${-pct}%)` : undefined,
    pointerEvents: 'none',
  };
};

// Aggressive background reset. We bypass tgui's <Pane>/<Layout> chrome
// entirely — those apply theme-driven gradients, NT-logo SVG, etc., that
// paint opaque pixels and ruin the BROWSER widget's transparency. The
// BROWSER element itself has inner-background-color=#00000000 set on the
// BYOND side; this CSS handles the document layer above it.
const RESET_CSS = `
html, body, #react-root, .BellyOverlayRoot,
div[class^="theme-"], .Layout, .Layout__content, .Window {
  background: transparent !important;
  background-image: none !important;
  margin: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  overflow: hidden !important;
}
html, body, #react-root, .BellyOverlayRoot {
  width: 100% !important;
  height: 100% !important;
  position: fixed !important;
  inset: 0 !important;
}
`;

export const BellyOverlay = (_props) => {
  const { data } = useBackend<Data>();
  const layers = data.layers || [];
  return (
    <div className="BellyOverlayRoot">
      <style>{RESET_CSS}</style>
      {data.visible &&
        layers.map((L, i) => (
          <div key={`${i}:${L.url}`} style={layerStyle(L)} />
        ))}
    </div>
  );
};
