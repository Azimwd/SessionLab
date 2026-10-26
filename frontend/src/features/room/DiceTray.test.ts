import { describe, expect, it } from 'vitest';
import { appendDie } from './DiceTray';
import { folderKey, folderOptions } from './folderOptions';

describe('dice picker', () => {
  it('accumulates same and mixed dice before the server roll', () => {
    expect(appendDie(appendDie('',20),20)).toBe('2d20');
    expect(appendDie(appendDie(appendDie('',20),10),10)).toBe('1d20+2d10');
    expect(appendDie('1d20+2d10',20)).toBe('2d20+2d10');
  });
});
it('groups dice actors in real folders and keeps unfiled sheets separate',()=>{
  const actors=[{id:1,folder:7,name:'Игрок'},{id:2,folder:undefined,name:'Страж'}];
  const options=folderOptions([{id:7,name:'Игроки'}],actors);
  expect(options).toContainEqual(['7','Игроки']);
  expect(options).toContainEqual(['unfiled','Без папки']);
  expect(actors.filter(a=>folderKey(a)==='unfiled').map(a=>a.name)).toEqual(['Страж']);
});
