import { WebPlugin } from '@capacitor/core';

import type { MultiAudioPlugin } from './definitions';

export class MultiAudioWeb extends WebPlugin implements MultiAudioPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
