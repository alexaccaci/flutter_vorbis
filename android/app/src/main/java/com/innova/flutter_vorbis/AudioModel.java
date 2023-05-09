package com.innova.flutter_vorbis;

import android.media.MediaPlayer;

public class AudioModel {
  private MediaPlayer mediaPlayer;
  private long playTime = 0;
  public int subsDurationMillis = 10;

  public MediaPlayer getMediaPlayer() {
    return mediaPlayer;
  }

  public void setMediaPlayer(MediaPlayer mediaPlayer) {
    this.mediaPlayer = mediaPlayer;
  }

  public long getPlayTime() {
    return playTime;
  }

  public void setPlayTime(long playTime) {
    this.playTime = playTime;
  }
}