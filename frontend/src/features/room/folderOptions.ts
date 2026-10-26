import type { Json } from '../../api/client';

export const folderKey = (character: Json) => character.folder == null ? 'unfiled' : String(character.folder);

export function folderOptions(folders: Json[], characters: Json[]) {
  const known = new Map<string, string>();
  for (const folder of folders) known.set(String(folder.id), folder.name);
  for (const character of characters) {
    const key = folderKey(character);
    if (!known.has(key) && character.folder_name) known.set(key, character.folder_name);
  }
  known.set('unfiled', 'Без папки');
  return [...known.entries()].filter(([key]) => key !== 'unfiled')
    .sort((a, b) => a[1].localeCompare(b[1], 'ru'))
    .concat([['unfiled', 'Без папки']]);
}
