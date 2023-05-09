import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'audio_plugin.dart';
import '../vorbis/wavheader.dart';

const int BUF_SIZE = 4096;

class PlayerAudio extends StatefulWidget {
  final List<Uint8List> slice;

  PlayerAudio(this.slice);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<PlayerAudio> {
  Duration? _duration;
  Duration? _position;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _audioPlayerStateSubscription;
  int _posAudio = 0;
  bool _stopped = true;
  bool _restart = false;
  bool _completed = true;
  double _percent = 0;
  bool _isInAsyncCall = false;
  Map<int, int> offsets = Map();
  Duration _offset = Duration(milliseconds: 0);
  int samples = 0;
  int samplerate = 0;
  int nchannel = 0;

  get durationText =>
      _duration != null ? _duration.toString().split('.').first : '';
  get positionText =>
      _position != null ? _position.toString().split('.').first : '';

  Duration calc(double pos) {
    return Duration(
        milliseconds:
            ((_duration != null ? _duration!.inMilliseconds : 0.0) * pos)
                .round());
  }

  stop(double pos) async {
    setState(() {
      _isInAsyncCall = true;
      _percent = pos;
      _stopped = true;
      _restart = false;
    });
    await audioPlugin.stop();
  }

  start(double pos) async {
    _stopped = false;
    _percent = pos;
    _restart = false;
    _completed = false;
    _offset = Duration(milliseconds: 0);
    _doAudioDownload(pos);
  }

  Uint8List deslice(List<Uint8List> list) {
    Uint8List retval = Uint8List(0);
    for (Uint8List item in list) retval = Uint8List.fromList(retval + item);
    return retval;
  }

  static int _getOffsetVal(Map<int, int> offsets, int val) {
    int retval = 0;
    var sortedKeys = offsets.keys.toList()..sort();
    for (int key in sortedKeys) {
      if (key < val)
        retval = offsets[key]!;
      else
        break;
    }
    return retval;
  }

  int _getAudioOffset(double pos, int nc) {
    int bytepersample = 2 * nc;
    int dim = _duration!.inSeconds * samplerate * bytepersample;
    int offsetPcm = ((dim * pos) / bytepersample).round() *
        bytepersample; //per non spezzare il pacchetto Pcm
    int posAudio = offsetPcm ~/ (4 * BUF_SIZE);
    print("PosAudio $posAudio");
    return posAudio;
  }

  _doAudioDownload(double pos) async {
    _posAudio = _getAudioOffset(pos, nchannel);
    await audioPlugin.init(samplerate, nchannel, vb: false);
    await audioPlugin.play();
    while (!_stopped && _posAudio < widget.slice.length) {
      if (_restart) {
        await audioPlugin.clear();
        setState(() {
          _restart = false;
          _offset = _position! + _offset - calc(_percent);
          print(_offset);
          _posAudio = _getAudioOffset(_percent, nchannel);
          _isInAsyncCall = false;
        });
      }
      await audioPlugin.write(widget.slice[_posAudio++]);
      if (_isInAsyncCall) {
        setState(() {
          _position = Duration(milliseconds: 0);
          _isInAsyncCall = false;
        });
      }
      if (!_stopped && await audioPlugin.queueLen() > 9)
        await Future.delayed(const Duration(milliseconds: 500));
      print("${DateTime.now()} doDownload $_posAudio");
    }
    await audioPlugin.write(Uint8List(0));
    _stopped = true;
    print("_doAudioDownload finish");
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _isInAsyncCall = true;
    });
    Uint8List bytes = deslice(widget.slice);
    List<int> list = WavHeader.getSamples(bytes);
    samples = list[0];
    print("InitState Samples $samples");
    samplerate = list[1];
    nchannel = list[2];
    _duration = Duration(seconds: samples ~/ samplerate);
    _positionSubscription = audioPlugin.onPlayerStateChanged.listen((p) {
      if (mounted && p != null)
        setState(() {
          _position = calc(_percent) + Duration(milliseconds: p.currentPosition.toInt()) - _offset;
        });
    });
    _audioPlayerStateSubscription = audioPlugin.onAudioStateChanged.listen((s) {
      if (s == AudioPlayerState.COMPLETED) {
        print("Arrivato onCompleted");
        setState(() {
          _completed = true;
          _percent = 0;
          _position = Duration(seconds: 0);
          _isInAsyncCall = false;
        });
      }
    });

    start(0);
    setState(() {
      _isInAsyncCall = false;
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _audioPlayerStateSubscription?.cancel();
    audioPlugin.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topAppBar = AppBar(
      title: Text("Audio"),
    );
    return Scaffold(
      appBar: topAppBar,
      body: Container(
        padding: EdgeInsets.all(16.0),
        child: _isInAsyncCall
            ? Center(child: CircularProgressIndicator())
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          onPressed: () {
                            if (audioPlugin.isPlaying) {
                              print("Pressed stop");
                              stop(0);
                            } else if (audioPlugin.isStopped ||
                                audioPlugin.isCompleted) {
                              print("Pressed start");
                              start(0);
                            }
                            setState(() {});
                          },
                          iconSize: 64.0,
                          icon: audioPlugin.isPlaying
                              ? Icon(Icons.stop)
                              : Icon(Icons.play_arrow),
                          color: Colors.cyan),
                    ]),
                    _duration == null
                        ? Container()
                        : Slider(
                            value: min(
                                _position?.inMilliseconds.toDouble() ?? 0.0,
                                _duration!.inMilliseconds.toDouble()),
                            min: 0.0,
                            max: _duration!.inMilliseconds.toDouble(),
                            onChanged: (double position) async {
                              if (_restart) return;
                              double pos = (position /
                                      _duration!.inMilliseconds.toDouble())
                                  .clamp(0.0, 1.0);
                              print('Audio_play $_completed percentage $pos');
                              if (_completed) {
                                await start(pos);
                              } else {
                                setState(() {
                                  _isInAsyncCall = true;
                                  _restart = true;
                                  _percent = pos;
                                });
                              }
                            }),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            _position != null
                                ? "${positionText ?? ''} / ${durationText ?? ''}"
                                : _duration != null
                                    ? durationText
                                    : '',
                            style: new TextStyle(fontSize: 24.0))
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
