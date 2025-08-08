import { WebPlugin } from '@capacitor/core';
import type { MultiAudioPlugin, MultiAudioTrack } from './definitions';

export class MultiAudioWeb extends WebPlugin implements MultiAudioPlugin {
  async loadTracks(_tracks: MultiAudioTrack[]): Promise<void> {
    console.warn('MultiAudio plugin web implementation not available');
  }
  async play(): Promise<void> {}
  async pause(): Promise<void> {}
  async seekTo(_seconds: number): Promise<void> {}
  async setVolume(_id: string, _volume: number): Promise<void> {}
  async getPosition(): Promise<{ currentTime: number; duration: number }> {
    return { currentTime: 0, duration: 0 };
  }
}
