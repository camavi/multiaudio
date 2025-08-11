import { WebPlugin } from '@capacitor/core';

import type { MultiAudioPlugin, MultiAudioTrack } from './definitions';

export class MultiAudioWeb extends WebPlugin implements MultiAudioPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
  async loadTracks(_tracks: MultiAudioTrack[]): Promise<void> {
    console.warn('MultiAudio plugin web implementation not available');
  }
  async play(): Promise<void> {
    throw this.unimplemented('Play is not implemented on web.');
  }
  async pause(): Promise<void> {
    throw this.unimplemented('Pause is not implemented on web.');
  }
  async seekTo(_seconds: number): Promise<void> {
    throw this.unimplemented('SeekTo is not implemented on web.');
  }
  async setVolume(_id: string, _volume: number): Promise<void> {
    throw this.unimplemented('SetVolume is not implemented on web.');
  }
  async getPosition(): Promise<{ currentTime: number; duration: number }> {
    return { currentTime: 0, duration: 0 };
  }
}
