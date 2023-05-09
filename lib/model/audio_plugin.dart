import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:f_logs/model/flog/flog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vorbis/vorbis/vorbisinterface.dart';
import 'package:path_provider/path_provider.dart';

enum AudioPlayerState {
  STOPPED,
  PLAYING,
  COMPLETED,
  PAUSED,
}

final audioPlugin = _AudioPlugin();

class _AudioPlugin {
  static const MethodChannel _channel =
      MethodChannel('com.innova.flutter/audio');

  static StreamController<int?>? _audioController;
  Stream<int?> get onAudioStateChanged => _audioController!.stream;
  int samplerate = 0;
  int nchannels = 0;
  int nbits = 0;
  bool isVorbis = false;
  Vorbis? vorbis;
  Duration? duration;
  int played = 0;

  static StreamController<PlayStatus?>? _playerController;
  Stream<PlayStatus?> get onPlayerStateChanged => _playerController!.stream;
  bool get isPlaying =>
      _audioState == AudioPlayerState.PLAYING ||
          _audioState == AudioPlayerState.PAUSED;
  bool get isPaused => _audioState == AudioPlayerState.PAUSED;
  bool get isStopped => _audioState == AudioPlayerState.STOPPED;
  bool get isCompleted => _audioState == AudioPlayerState.COMPLETED;
  AudioPlayerState get audioState => _audioState;
  AudioPlayerState _audioState = AudioPlayerState.STOPPED;

  _AudioPlugin();

  int getMillisec(int len) {
    int msec = (8000 * len / samplerate / nchannels / nbits).round();
    if (msec > 200)
      msec -= 200;
    else
      msec = 0;
    print("GetMillisec $msec");
    return msec;
  }

  init(int sr, int nc, {bool vb = false, int nb = 16}) async {
    try {
      played = 0;
      samplerate = sr;
      nchannels = nc;
      nbits = nb;
      isVorbis = vb;
      if (isVorbis) vorbis = Vorbis();
      _removeAudioCallback();
      _removePlayerCallback();
      _setAudioCallback();
      await _channel.invokeMethod('init',
          {'samplerate': samplerate, 'nchannels': nchannels, 'nbits': nbits});
    } on PlatformException catch (e) {
      FLog.error(
          className: "audio_plugin", methodName: "init", text: "Error init $e");
    }
  }

  write(Uint8List buffer, {bool play = true}) async {
    try {
      if (isVorbis) {
        int size = vorbis!.sliceBuffer(buffer);
        if (play && size > 0) {
          played += size;
          await _channel.invokeMethod(
              'write', {'buffer': vorbis!.bufferConv, 'size': size});
        }
        if (buffer.length == 0) {
          await _channel
              .invokeMethod('write', {'buffer': buffer, 'size': buffer.length});
        }
      } else {
        played += buffer.length;
        await _channel
            .invokeMethod('write', {'buffer': buffer, 'size': buffer.length});
      }
    } on PlatformException catch (e) {
      _audioState = AudioPlayerState.STOPPED;
      FLog.error(
          className: "audio_plugin",
          methodName: "write",
          text: "Error write $e");
    }
  }

  play() async {
    try {
      await _channel.invokeMethod('play');
    } on PlatformException catch (e) {
      _audioState = AudioPlayerState.STOPPED;
      FLog.error(
          className: "audio_plugin", methodName: "play", text: "Error play $e");
    }
  }

  pause() async {
    try {
      await _channel.invokeMethod('pause');
    } on PlatformException catch (e) {
      _audioState = AudioPlayerState.STOPPED;
      FLog.error(
          className: "audio_plugin", methodName: "pause", text: "Error pause $e");
    }
  }

  clear() async {
    try {
      await _channel.invokeMethod('clear');
    } on PlatformException catch (e) {
      FLog.error(
          className: "audio_plugin",
          methodName: "clear",
          text: "Error clear $e");
    }
  }

  stop() async {
    try {
      //if(isVorbis) vorbis.clean();
      await _channel.invokeMethod('stop');
    } on PlatformException catch (e) {
      _audioState = AudioPlayerState.STOPPED;
      FLog.error(
          className: "audio_plugin", methodName: "stop", text: "Error stop $e");
    }
  }

  Future<int> queueLen() async {
    int retval = 0;
    try {
      retval = await _channel.invokeMethod('queueLen');
      print("queueLen $retval");
    } on PlatformException catch (e) {
      FLog.error(
          className: "audio_plugin",
          methodName: "queuelen",
          text: "Error queueLen $e");
    }
    return retval;
  }

  Future<void> _setAudioCallback() async {
    _audioController ??= StreamController.broadcast();
    _channel.setMethodCallHandler((MethodCall call) {
    switch (call.method) {
      case "audio.onCurrentPosition":
        //assert(_state == AudioPlayerState.PLAYING);
        //print("currentpos ${call.arguments}");
          _audioController!.add(call.arguments);
        break;
      case "audio.onStart":
        print("audio_plugin _audioPlayerStateChange onstart");
        _audioState = AudioPlayerState.PLAYING;
          _audioController!.add(call.arguments);
        break;
      case "audio.onStop":
        print("audio_plugin _audioPlayerStateChange onstop");
        _audioState = AudioPlayerState.STOPPED;
          _audioController!.add(call.arguments);
        break;
      case "audio.onPause":
        print("audio_plugin _audioPlayerStateChange onpause");
        _audioState = AudioPlayerState.PAUSED;
          _audioController!.add(call.arguments);
        break;
      case "audio.onComplete":
        print("audio_plugin _audioPlayerStateChange oncomplete");
        _audioState = AudioPlayerState.COMPLETED;
          _audioController!.add(call.arguments);
          _removeAudioCallback();
        break;
      default:
          throw ArgumentError('Unknown method ${call.method}');
      }
      return call.arguments;
    });
  }

  _removeAudioCallback() {
    if (_audioController != null) {
      _audioController!
        ..add(null)
        ..close();
      _audioController = null;
    }
  }

  Future<String> setSubscriptionDuration(double sec) async {
    String result = await _channel
        .invokeMethod('setSubscriptionDuration', <String, dynamic>{
      'sec': sec,
    });
    return result;
  }

  Future<void> _setPlayerCallback() async {
    _playerController ??= StreamController.broadcast();
    _channel.setMethodCallHandler((MethodCall call) {
      switch (call.method) {
        case "updateProgress":
          Map<String, dynamic> result = jsonDecode(call.arguments);
          if (_playerController!=null) {
            _playerController!.add(PlayStatus.fromJSON(result));
          }
          break;
        case "audioPlayerDidFinishPlaying":
          Map<String, dynamic> result = jsonDecode(call.arguments);
          PlayStatus status = PlayStatus.fromJSON(result);
          if (status.currentPosition != status.duration) {
            status.currentPosition = status.duration;
          }
          if (_playerController != null) _playerController!.add(status);
          _audioState = AudioPlayerState.STOPPED;
          _removePlayerCallback();
          break;
        default:
          throw ArgumentError('Unknown method ${call.method}');
      }
      return call.arguments;
    });
  }

  Future<void> _removePlayerCallback() async {
    if (_playerController != null) {
      _playerController!
        ..add(null)
        ..close();
      _playerController = null;
    }
  }

  Future<String?> getFFmpegVersion() async {
    try {
      final result = await _channel.invokeMethod<String>('getFFmpegVersion');
      return result;
    } on PlatformException catch (e) {
      FLog.error(
          className: "audio_plugin",
          methodName: "getFFmpegVersion",
          text: "Error version $e");
      return null;
    }
  }

  /// Executes FFmpeg with `commandArguments` provided.
  Future<int> executeWithArguments(List<String> arguments) async {
    try {
      final result = await _channel.invokeMethod<int>(
          'executeFFmpegWithArguments', {'arguments': arguments});
      return result!;
    } on PlatformException catch (e) {
      FLog.error(
          className: "audio_plugin",
          methodName: "executeFFmpegWithArguments",
          text: "Error execute $e");
      return -1;
    }
  }

  /// Convert a opus to caf.
  Future<int> opusToCaf(String inputFile, String outputFile) async {
    return await executeWithArguments([
      '-loglevel',
      'error',
      '-y',
      '-i',
      inputFile,
      '-c:a',
      'copy',
      outputFile,
    ]); // remux OGG to CAF
  }

  Future<String?> startPlayer(String path) async {
    String? result;
    if (_audioState == AudioPlayerState.PAUSED) {
      resumePlayer();
      _audioState = AudioPlayerState.PLAYING;
      return 'Player resumed';
      // throw PlayerRunningException('Player is already playing.');
    }
    if (_audioState != AudioPlayerState.STOPPED && _audioState != AudioPlayerState.COMPLETED) {
      throw PlayerRunningException('Player is not stopped.');
    }

    try {
      if (Platform.isIOS && path.endsWith('.opus')) {
        Directory tempDir = await getTemporaryDirectory ();
        File fout = File('${tempDir.path}/audio-tmp.caf');
        if (fout.existsSync()) {
          await fout.delete();
        }
        int rc = await opusToCaf(path, fout.path); // remux OGG to CAF
        if (rc != 0) {
          FLog.error(
              className: "audio_plugin",
              methodName: "startPlayer",
              text: "Error opusToCaf $rc");
          return null;
        }
        // Now we can play Apple CAF/OPUS
        result =
            await _channel.invokeMethod('startPlayer', {'path': fout.path});
      } else {
        result = await _channel.invokeMethod('startPlayer', {'path': path});
      }

      if (result != null) {
        print ('startPlayer result: $result');
        _setPlayerCallback ();
        _audioState = AudioPlayerState.PLAYING;
      }

      return result;
    } catch (err) {
      FLog.error(
          className: "audio_plugin",
          methodName: "startPlayer",
          text: "Error write $err");
      throw Exception(err);
    }
  }

  Future<String?> stopPlayer() async {
    if (_audioState != AudioPlayerState.PAUSED &&
        _audioState != AudioPlayerState.PLAYING) {
      throw PlayerRunningException('Player is not playing.');
    }

    _audioState = AudioPlayerState.STOPPED;

    final result = await _channel.invokeMethod('stopPlayer');
    _removePlayerCallback();
    return result;
  }

  Future<String?> pausePlayer() async {
    if (_audioState != AudioPlayerState.PLAYING) {
      throw PlayerRunningException('Player is not playing.');
    }

    try {
      final result = await _channel.invokeMethod('pausePlayer');
      if (result != null) _audioState = AudioPlayerState.PAUSED;
      return result;
    } catch (err) {
      FLog.error(
          className: "audio_plugin",
          methodName: "pausePlayer",
          text: "Error write $err");
            _audioState = AudioPlayerState
          .STOPPED; // In fact _audioState is in an unknown state

      throw Exception(err);
    }
  }

  Future<String?> resumePlayer() async {
    if (_audioState != AudioPlayerState.PAUSED) {
      throw PlayerRunningException('Player is not paused.');
    }

    try {
      final result = await _channel.invokeMethod('resumePlayer');
      if (result != null) _audioState = AudioPlayerState.PLAYING;
      return result;
    } catch (err) {
      FLog.error(
          className: "audio_plugin",
          methodName: "resumePlayer",
          text: "Error write $err");
      throw Exception(err);
    }
  }

  Future<String?> seekToPlayer(int milliSecs) async {
    try {
      final result =
      await _channel.invokeMethod('seekToPlayer', <String, dynamic>{
        'sec': milliSecs,
      });
      return result;
    } catch (err) {
      FLog.error(
          className: "audio_plugin",
          methodName: "seekToPlayer",
          text: "Error write $err");
      throw Exception(err);
    }
  }

  Future<String?> setVolume(double volume) async {
    double indexedVolume = Platform.isIOS ? volume * 100 : volume;
    String? result = '';
    if (volume < 0.0 || volume > 1.0) {
      result = 'Value of volume should be between 0.0 and 1.0.';
      return result;
    }

    result = await _channel.invokeMethod('setVolume', <String, dynamic>{
      'volume': indexedVolume,
    });
    return result;
  }

  Future<String?> addSSLCertificate(String cert) async {
    try {
      final result =
          await _channel.invokeMethod('addSSLCertificate', {'cert': cert});
      FLog.info(
          className: "audio_plugin",
          methodName: "addSSLCertificate",
          text: "$result");
      return result;
    } catch (err) {
      FLog.error(
          className: "audio_plugin",
          methodName: "addSSLCertificate",
          text: "Error load certificate $err");
      throw Exception(err);
    }
  }

  Future<bool> isBiometricConfigured() async {
    if(Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod('isBiometricConfigured');
        FLog.info(
            className: "audio_plugin",
            methodName: "isBiometricConfigured",
            text: "$result");
        return result == "true";
      } catch (err) {
        FLog.error(
            className: "audio_plugin",
            methodName: "isBiometricConfigured",
            text: "Error test biometric $err");
      }
    }
    else if(Platform.isIOS) {
      return true;
    }
    return false;
  }
}

class PlayStatus {
  final double duration;
  double currentPosition;

  PlayStatus.fromJSON(Map<String, dynamic> json)
      : duration = double.parse(json['duration']),
        currentPosition = double.parse(json['current_position']);

  @override
  String toString() {
    return 'duration: $duration, '
        'currentPosition: $currentPosition';
  }
}

class PlayerRunningException implements Exception {
  final String message;
  PlayerRunningException(this.message);
}

class PlayerStoppedException implements Exception {
  final String message;
  PlayerStoppedException(this.message);
}
