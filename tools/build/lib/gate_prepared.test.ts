import { expect, test } from 'bun:test';
import { gatePrepared } from './gate_prepared';

const head = () => 'abc';
const clean = () => false;
test('the commit the gate prepared, clean: skipped', () => expect(gatePrepared(head, clean, 'abc')).toBe(true));
test('another commit runs the steps', () => expect(gatePrepared(head, clean, 'def')).toBe(false));
test('no gate runs the steps', () => expect(gatePrepared(head, clean, undefined)).toBe(false));
test('a dirty tree runs the steps', () => expect(gatePrepared(head, () => true, 'abc')).toBe(false));
