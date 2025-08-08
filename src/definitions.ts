export interface MultiAudioTrack {
  id: string;
  url: string;
  volume: number;
  isMaster?: boolean;
}

export interface MultiAudioPlugin {
  loadTracks(tracks: MultiAudioTrack[]): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  seekTo(seconds: number): Promise<void>;
  setVolume(id: string, volume: number): Promise<void>;
  getPosition(): Promise<{ currentTime: number; duration: number }>;
}
