import { SQL } from 'bun';
import { config } from './config';

export const db = new SQL(config.databaseUrl);

/** A parameterized query with `?` placeholders, for statements built with variable-length lists. */
export function query<T = Record<string, unknown>>(
  text: string,
  params: unknown[] = [],
): Promise<T[]> {
  return db.unsafe(text, params) as Promise<T[]>;
}

/** `?, ?, ?` for a list of n values. */
export const placeholders = (n: number) =>
  Array.from({ length: n }, () => '?').join(', ');
