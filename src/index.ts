import { registerPlugin } from '@capacitor/core';
import type { MultiAudioPlugin } from './definitions';

const MultiAudio = registerPlugin<MultiAudioPlugin>('MultiAudio', {
  web: () => import('./web').then((m) => new m.MultiAudioWeb()),
});

export * from './definitions';
export { MultiAudio };
