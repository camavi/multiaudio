export interface MultiAudioPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
