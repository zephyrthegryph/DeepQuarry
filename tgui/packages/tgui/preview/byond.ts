// A stand-in for the BYOND page object so a window renders in an ordinary browser (tools/tgui_preview).
const noop = () => {};
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
  winset: noop,
  parseJson: (text: string) => JSON.parse(text),
  sendMessage: noop,
  subscribe: () => noop,
  subscribeTo: () => noop,
  loadCss: noop,
  loadJs: noop,
  iconRefMap: {},
  saveBlob: noop,
};
