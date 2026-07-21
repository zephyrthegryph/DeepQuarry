export type InterfacePreparer = (name: string) => Promise<void> | undefined;

let interfacePreparer: InterfacePreparer | undefined;

/** Registers the route loader without coupling backend handlers to routes.tsx. */
export function registerInterfacePreparer(
  preparer: InterfacePreparer | undefined,
): void {
  interfacePreparer = preparer;
}

/** Returns undefined when the interface is already synchronously renderable. */
export function prepareRequestedInterface(
  name: string | undefined,
): Promise<void> | undefined {
  if (!name || !interfacePreparer) return;
  return interfacePreparer(name);
}
