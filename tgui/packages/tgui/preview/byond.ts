// A stand-in for the BYOND page object so a window renders in an ordinary browser (tools/tgui_preview).
const noop = () => {};
// A seeded Math.random (mulberry32), so a window that picks a tip or an ad at random draws the same shot every run.
let seed = 0x5eed;
Math.random = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const geometry = { size: { x: 560, y: 640 }, pos: { x: 0, y: 0 } };
(globalThis as any).Byond = {
  windowId: 'preview',
  IS_BYOND: false,
  BLINK: false,
  strictMode: false,
  storageCdn: '',
  call: () => ({}),
  callAsync: async () => ({}),
  topic: noop,
  command: noop,
  winget: async () => geometry,
  // The window's own size request (Window width/height) is what the harness must lay it out at.
  winset: (_id: string, opts: any) => {
    const m = String(opts?.size ?? '').match(/^(\d+)x(\d+)$/);
    const size = m
      ? [Number(m[1]), Number(m[2])]
      : Array.isArray(opts?.size)
        ? opts.size
        : null;
    if (size) {
      (globalThis as any).__previewSize = size; // read by tools/tgui_preview/render.ts
      parent.postMessage({ sizeRequest: size }, '*');
    }
  },
  parseJson: (text: string) => JSON.parse(text),
  sendMessage: noop,
  subscribe: () => noop,
  subscribeTo: () => noop,
  // A spritesheet a window asks for at run time (the sprite cache serves every sheet beside the bundle).
  loadCss: (href: string) => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = href;
    document.head.appendChild(link);
  },
  loadJs: noop,
  // DmIcon asks for `<ref>?state=..&dir=..&frame=..`: each .dmi path is a ref the render server crops to that frame.
  iconRefMap: new Proxy({} as Record<string, string>, {
    get: (_t, key) => (typeof key === 'string' ? `dmi/${key}` : undefined),
    has: () => true,
  }),
  saveBlob: noop,
};
