export type StaticWindowGeometry = {
  width: number;
  height: number;
  exact: boolean;
};

/**
 * Default native geometry shared by DreamDaemon and the React window layout.
 *
 * Entries here are emitted into tgui-window-manifest.json at build time. Interfaces
 * with state-dependent dimensions use this as their safe initial size and may still
 * pass an explicit width/height to <Window> for a particular state.
 */
declare const __TGUI_WINDOW_GEOMETRY_MANIFEST__: Record<
  string,
  StaticWindowGeometry
>;

// The bundler defines the manifest; a bare module load (the unit tests) has none.
export const staticWindowGeometry: Record<string, StaticWindowGeometry> =
  typeof __TGUI_WINDOW_GEOMETRY_MANIFEST__ === 'undefined'
    ? {}
    : __TGUI_WINDOW_GEOMETRY_MANIFEST__;

export function getStaticWindowGeometry(
  interfaceName?: string,
): StaticWindowGeometry | undefined {
  return interfaceName ? staticWindowGeometry[interfaceName] : undefined;
}
