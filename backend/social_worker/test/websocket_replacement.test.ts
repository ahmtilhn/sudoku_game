import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('durable object websocket replacement', () => {
  it('accepts the new socket before closing stale sockets', () => {
    const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
    const capture = source.indexOf('const replacedSockets = this.state.getWebSockets(playerId);');
    const accept = source.indexOf('this.state.acceptWebSocket(server, [playerId]);');
    const closeLoop = source.indexOf('for (const socket of replacedSockets)');
    expect(capture).toBeGreaterThanOrEqual(0);
    expect(accept).toBeGreaterThan(capture);
    expect(closeLoop).toBeGreaterThan(accept);
  });

  it('does not mark a player disconnected when a replacement socket is open', () => {
    const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
    expect(source).toContain('const hasReplacementSocket = this.state');
    expect(source).toContain('candidate !== socket && candidate.readyState === 1');
    expect(source).toContain('if (hasReplacementSocket) return;');
  });
});
