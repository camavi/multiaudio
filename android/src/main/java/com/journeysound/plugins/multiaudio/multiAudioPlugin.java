package com.journeysound.plugins.multiaudio;

import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.annotation.CapacitorPlugin;

import com.google.android.exoplayer2.ExoPlayer;
import com.google.android.exoplayer2.MediaItem;

import java.util.HashMap;
import java.util.Map;

@CapacitorPlugin(name = "MultiAudio")
public class MultiAudioPlugin extends Plugin {

    private Map<String, ExoPlayer> players = new HashMap<>();
    private String masterId = null;
    private boolean isPlaying = false;
    private Handler handler = new Handler(Looper.getMainLooper());

    @Override
    public void load() {
        // Optional initialization
    }

    @PluginMethod
    public void loadTracks(PluginCall call) {
        JSObject[] tracks = call.getArray("tracks", JSObject[].class);
        if (tracks == null) {
            call.reject("Missing tracks array");
            return;
        }
        for (JSObject track : tracks) {
            String id = track.getString("id");
            String url = track.getString("url");
            Double volume = track.getDouble("volume");
            Boolean isMaster = track.getBoolean("isMaster");
            if (id == null || url == null || volume == null) continue;

            ExoPlayer player = new ExoPlayer.Builder(getContext()).build();
            MediaItem mediaItem = MediaItem.fromUri(Uri.parse(url));
            player.setMediaItem(mediaItem);
            player.prepare();
            player.setVolume(volume.floatValue());
            players.put(id, player);

            if (isMaster != null && isMaster) {
                masterId = id;
            }
        }
        call.resolve();
    }

    @PluginMethod
    public void play(PluginCall call) {
        if (isPlaying) {
            call.resolve();
            return;
        }
        if (masterId == null || !players.containsKey(masterId)) {
            call.reject("Master track not loaded");
            return;
        }

        long masterPosition = players.get(masterId).getCurrentPosition();
        for (Map.Entry<String, ExoPlayer> entry : players.entrySet()) {
            ExoPlayer player = entry.getValue();
            player.seekTo(masterPosition);
            player.play();
        }
        isPlaying = true;
        call.resolve();
    }

    @PluginMethod
    public void pause(PluginCall call) {
        if (!isPlaying) {
            call.resolve();
            return;
        }
        for (ExoPlayer player : players.values()) {
            player.pause();
        }
        isPlaying = false;
        call.resolve();
    }

    @PluginMethod
    public void seekTo(PluginCall call) {
        Double seconds = call.getDouble("seconds");
        if (seconds == null) {
            call.reject("Missing seconds parameter");
            return;
        }
        long posMs = (long)(seconds * 1000);
        for (ExoPlayer player : players.values()) {
            player.seekTo(posMs);
        }
        call.resolve();
    }

    @PluginMethod
    public void setVolume(PluginCall call) {
        String id = call.getString("id");
        Double volume = call.getDouble("volume");
        if (id == null || volume == null || !players.containsKey(id)) {
            call.reject("Invalid id or volume");
            return;
        }
        players.get(id).setVolume(volume.floatValue());
        call.resolve();
    }

    @PluginMethod
    public void getPosition(PluginCall call) {
        if (masterId == null || !players.containsKey(masterId)) {
            JSObject ret = new JSObject();
            ret.put("currentTime", 0);
            ret.put("duration", 0);
            call.resolve(ret);
            return;
        }
        ExoPlayer master = players.get(masterId);
        JSObject ret = new JSObject();
        ret.put("currentTime", master.getCurrentPosition() / 1000.0);
        ret.put("duration", master.getDuration() / 1000.0);
        call.resolve(ret);
    }
}

