import { describe, expect, it } from 'vitest';
import { appendDie } from './DiceTray';

describe('dice picker', () => {
  it('accumulates same and mixed dice before the server roll', () => {
    expect(appendDie(appendDie('',20),20)).toBe('2d20');
    expect(appendDie(appendDie(appendDie('',20),10),10)).toBe('1d20+2d10');
    expect(appendDie('1d20+2d10',20)).toBe('2d20+2d10');
  });
});
