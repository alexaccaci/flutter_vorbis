package com.innova.flutter_vorbis;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaPlayer;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Handler;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Arrays;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterActivity {
  private static final String CHANNEL = "com.innova.flutter/audio";
  private static final String TAG = "MainActivity";
  private MethodChannel channel;
  int samplerate;
  int nchannels;
  int nbits;
  int minBuffer;
  PlayTask playtask;
  AudioTrack audioTrack;
  LinkedBlockingQueue<byte[]> audioqueue = new LinkedBlockingQueue<>();
  private final Handler handler = new Handler();

  private static final String ERR_UNKNOWN = "ERR_UNKNOWN";
  private static final String ERR_PLAYER_IS_NULL = "ERR_PLAYER_IS_NULL";
  private static final String ERR_PLAYER_IS_PLAYING = "ERR_PLAYER_IS_PLAYING";
  final static int CODEC_OPUS = 2;
  final static int CODEC_VORBIS = 5;
  final private AudioModel model = new AudioModel();
  private Timer mTimer = new Timer();
  static boolean _isAndroidDecoderSupported [] = {
          true, // DEFAULT
          true, // AAC
          true, // OGG/OPUS
          false, // CAF/OPUS
          true, // MP3
          true, // OGG/VORBIS
          true, // WAV/PCM
  };

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(
            new MethodChannel.MethodCallHandler() {
              @Override
              public void onMethodCall(MethodCall call, MethodChannel.Result result) {
                switch (call.method) {
                  case "init":
                      samplerate = call.argument("samplerate");
                      nchannels = call.argument("nchannels");
                      nbits = call.argument("nbits");
                      minBuffer = AudioTrack.getMinBufferSize(samplerate, getChannelOut(nchannels), getEncodingOut(nbits));
                      Log.i(TAG, "Audio rate " + samplerate + " channels " + nchannels + " bits " + nbits + " buf " + minBuffer);
                      result.success(null);
                    break;
                  case "write":
                    //Log.i(TAG, "Audio write called");
                    int size = call.argument("size");
                    byte[] buffer = call.argument("buffer");
                    audioqueue.add(Arrays.copyOf(buffer, size));
                    //Log.v(TAG,"queue "+size);
                    result.success(null);
                    break;
                  case "play":
                    Log.i(TAG, "Audio play called");
                    if(playtask == null) {
                      (playtask = new PlayTask()).execute();
                      Log.i(TAG, "New audio play");
                      result.success(null);
                    }
                    else
                    {
                      Log.i(TAG, "Audio is playing");
                      result.error("Audio is playing",null,null);
                    }
                    break;
                  case "pause":
                    Log.i(TAG, "Audio pause called");
                    if(playtask != null) {
                      audioTrack.pause();
                      channel.invokeMethod("audio.onPause", null);
                      result.success(null);
                    }
                    else {
                      Log.i(TAG, "Audio is not playing");
                      result.error("Audio is not playing",null,null);
                    }
                    break;
                  case "stop":
                    Log.i(TAG, "Audio stop called");
                    if(playtask != null) {
                      playtask.setStopped();
                      channel.invokeMethod("audio.onStop", null);
                      result.success(null);
                    }
                    else {
                      Log.i(TAG, "Audio is not playing");
                      result.error("Audio is not playing",null,null);
                    }
                    break;
                  case "clear":
                    if(playtask != null) {
                      audioTrack.pause();
                      audioqueue.clear();
                      audioTrack.flush();
                      audioTrack.play();
                      result.success(null);
                    }
                    else {
                      Log.i(TAG, "Audio is not playing");
                      result.error("Audio is not playing",null,null);
                    }
                    break;
                  case "queueLen":
                    //Log.i(TAG, "Audio queueLen called");
                    result.success(audioqueue.size());
                    break;

                  case "isDecoderSupported": {
                    int _codec = call.argument("codec");
                    boolean b = _isAndroidDecoderSupported[_codec];
                    if (Build.VERSION.SDK_INT < 23) {
                      if ( (_codec == CODEC_OPUS) || (_codec == CODEC_VORBIS) )
                        b = false;
                    }

                    result.success(b);
                  } break;
                  case "startPlayer":
                    final String path = call.argument("path");
                    startPlayer(path, result);
                    break;
                  case "stopPlayer":
                    stopPlayer(result);
                    break;
                  case "pausePlayer":
                    pausePlayer(result);
                    break;
                  case "resumePlayer":
                    resumePlayer(result);
                    break;
                  case "seekToPlayer":
                    int sec = call.argument("sec");
                    seekToPlayer(sec, result);
                    break;
                  case "setVolume":
                    double volume = call.argument("volume");
                    setVolume(volume, result);
                    break;
                  case "setSubscriptionDuration":
                    if (call.argument("sec") == null) return;
                    double duration = call.argument("sec");
                    setSubscriptionDuration(duration, result);
                    break;

                  default:
                    result.notImplemented();
                    break;
                }//switch
              }
            });
  }

  private static String printBytes(byte[] msg, int len) {
    String retval = "";
    for (int i = 0; i < len; i++)
      retval += String.format("%02X", msg[i]);
    return retval;
  }

  private static int getMillisecBuffer(int sec, int samplerate, int nchannels, int nbits) {
    int retval = sec * samplerate * nchannels * nbits / 8000;
    Log.i(TAG, "GetMillisecBuffer " + retval);
    return retval;
  }

  private static int getChannelOut(int nchannels) {
    if (nchannels == 2)
      return AudioFormat.CHANNEL_OUT_STEREO;
    return AudioFormat.CHANNEL_OUT_MONO;
  }

  private static int getEncodingOut(int nbits) {
    if (nbits == 16)
      return AudioFormat.ENCODING_PCM_16BIT;
    return AudioFormat.ENCODING_PCM_8BIT;
  }

  class PlayTask extends AsyncTask<Void, Void, Void> {

    boolean stopped = false;

        @Override
    protected void onPreExecute() {
      channel.invokeMethod("audio.onStart", null);
    }

    @Override
    protected Void doInBackground(Void... params) {
      //Thread.currentThread().setPriority(Thread.MAX_PRIORITY);
      audioTrack = new AudioTrack(AudioManager.STREAM_MUSIC,
              samplerate, getChannelOut(nchannels), getEncodingOut(nbits),
              minBuffer, AudioTrack.MODE_STREAM);
      audioTrack.play();
      handler.post(sendData);
      while (!stopped) {
        try {
          byte[] buffer = audioqueue.poll(200, TimeUnit.MILLISECONDS);
          if (buffer != null) {
            Log.v(TAG, "write " + buffer.length);
            if(buffer.length > 0)
              audioTrack.write(buffer, 0, buffer.length);
            else
              stopped = true;
          }
        } catch (Exception e) {
          e.printStackTrace();
        }
      }
      playtask = null;
      handler.removeCallbacks(sendData);
      audioTrack.pause();
      audioTrack.flush();
      audioTrack.stop();
      audioTrack.release();
      audioTrack = null;
      audioqueue.clear();
      return null;
    }

    @Override
    protected void onPostExecute(Void result) {
      channel.invokeMethod("audio.onComplete", null);
    }

    public void setStopped() {
      stopped = true;
    }

    private final Runnable sendData = new Runnable(){
      public void run(){
        try {
          int time = (int) (1000F * audioTrack.getPlaybackHeadPosition() / samplerate);
          //Log.v(TAG, "headpops " + time);
          channel.invokeMethod("audio.onCurrentPosition", time);
          handler.postDelayed(this, 200);
        }
        catch (Exception e) {
          Log.w(TAG, "When running handler", e);
        }
      }
    };
  }


  public void startPlayer(final String path, final MethodChannel.Result result) {
    if (this.model.getMediaPlayer() != null) {
      Boolean isPaused = !this.model.getMediaPlayer().isPlaying()
              && this.model.getMediaPlayer().getCurrentPosition() > 1;

      if (isPaused) {
        this.model.getMediaPlayer().start();
        result.success("player resumed.");
        return;
      }

      Log.e(TAG, "Player is already running. Stop it first.");
      result.success("player is already running.");
      return;
    } else {
      this.model.setMediaPlayer(new MediaPlayer());
    }
    mTimer = new Timer();

    try {

      this.model.getMediaPlayer().setDataSource(path);

      this.model.getMediaPlayer().setOnPreparedListener(mp -> {
        Log.d(TAG, "mediaPlayer prepared and start");
        mp.start();

        /*
         * Set timer task to send event to RN.
         */
        TimerTask mTask = new TimerTask() {
          @Override
          public void run() {
            // long time = mp.getCurrentPosition();
            // DateFormat format = new SimpleDateFormat("mm:ss:SS", Locale.US);
            // final String displayTime = format.format(time);
            try {
              JSONObject json = new JSONObject();
              json.put("duration", String.valueOf(mp.getDuration()));
              json.put("current_position", String.valueOf(mp.getCurrentPosition()));
              handler.post(new Runnable() {
                @Override
                public void run() {
                  channel.invokeMethod("updateProgress", json.toString());
                }
              });

            } catch (JSONException je) {
              Log.d(TAG, "Json Exception: " + je.toString());
            }
          }
        };

        mTimer.schedule(mTask, 0, model.subsDurationMillis);
        result.success((path));
      });
      /*
       * Detect when finish playing.
       */
      this.model.getMediaPlayer().setOnCompletionListener(mp -> {
        /*
         * Reset player.
         */
        Log.d(TAG, "Plays completed.");
        try {
          JSONObject json = new JSONObject();
          json.put("duration", String.valueOf(mp.getDuration()));
          json.put("current_position", String.valueOf(mp.getCurrentPosition()));
          channel.invokeMethod("audioPlayerDidFinishPlaying", json.toString());
        } catch (JSONException je) {
          Log.d(TAG, "Json Exception: " + je.toString());
        }
        mTimer.cancel();
        if(mp.isPlaying())
        {
          mp.stop();
        }
        mp.reset();
        mp.release();
        model.setMediaPlayer(null);
      });
      this.model.getMediaPlayer().prepare();
    } catch (Exception e) {
      Log.e(TAG, "startPlayer() exception");
      result.error(ERR_UNKNOWN, ERR_UNKNOWN, e.getMessage());
    }
  }

  public void stopPlayer(final MethodChannel.Result result) {
    mTimer.cancel();

    if (this.model.getMediaPlayer() == null) {
      result.error(ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL);
      return;
    }

    try {
      this.model.getMediaPlayer().stop();
      this.model.getMediaPlayer().reset();
      this.model.getMediaPlayer().release();
      this.model.setMediaPlayer(null);
      result.success("stopped player.");
    } catch (Exception e) {
      Log.e(TAG, "stopPlay exception: " + e.getMessage());
      result.error(ERR_UNKNOWN, ERR_UNKNOWN, e.getMessage());
    }
  }

  public void pausePlayer(final MethodChannel.Result result) {
    if (this.model.getMediaPlayer() == null) {
      result.error(ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL);
      return;
    }

    try {
      this.model.getMediaPlayer().pause();
      result.success("paused player.");
    } catch (Exception e) {
      Log.e(TAG, "pausePlay exception: " + e.getMessage());
      result.error(ERR_UNKNOWN, ERR_UNKNOWN, e.getMessage());
    }
  }

  public void resumePlayer(final MethodChannel.Result result) {
    if (this.model.getMediaPlayer() == null) {
      result.error(ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL);
      return;
    }

    if (this.model.getMediaPlayer().isPlaying()) {
      result.error(ERR_PLAYER_IS_PLAYING, ERR_PLAYER_IS_PLAYING, ERR_PLAYER_IS_PLAYING);
      return;
    }

    try {
      this.model.getMediaPlayer().seekTo(this.model.getMediaPlayer().getCurrentPosition());
      this.model.getMediaPlayer().start();
      result.success("resumed player.");
    } catch (Exception e) {
      Log.e(TAG, "mediaPlayer resume: " + e.getMessage());
      result.error(ERR_UNKNOWN, ERR_UNKNOWN, e.getMessage());
    }
  }

  public void seekToPlayer(int millis, final MethodChannel.Result result) {
    if (this.model.getMediaPlayer() == null) {
      result.error(ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL);
      return;
    }

    int currentMillis = this.model.getMediaPlayer().getCurrentPosition();
    Log.d(TAG, "currentMillis: " + currentMillis);
    // millis += currentMillis; [This was the problem for me]

    Log.d(TAG, "seekTo: " + millis);

    this.model.getMediaPlayer().seekTo(millis);
    result.success(String.valueOf(millis));
  }

  public void setVolume(double volume, final MethodChannel.Result result) {
    if (this.model.getMediaPlayer() == null) {
      result.error(ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL, ERR_PLAYER_IS_NULL);
      return;
    }

    float mVolume = (float) volume;
    this.model.getMediaPlayer().setVolume(mVolume, mVolume);
    result.success("Set volume");
  }

  public void setSubscriptionDuration(double sec, final MethodChannel.Result result) {
    this.model.subsDurationMillis = (int) (sec * 1000);
    result.success("setSubscriptionDuration: " + this.model.subsDurationMillis);
  }
}
