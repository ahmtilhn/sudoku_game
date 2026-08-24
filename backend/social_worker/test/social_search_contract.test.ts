import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const indexSource = readFileSync(
  new URL('../src/index.ts', import.meta.url),
  'utf8',
);

describe('social player search contract', () => {
  it('finds players by public friend id as well as username', () => {
    expect(indexSource).toContain('const publicIdQuery = normalizePublicId(rawQuery)');
    expect(indexSource).toContain('OR p.public_id LIKE ?');
    expect(indexSource).toContain('WHEN p.public_id = ? THEN 0');
  });
});
