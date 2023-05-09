import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:f_logs/model/flog/flog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart';
import '../vorbis/vorbisinterface.dart';
import 'audio_plugin.dart';

enum PlayerVorbisMode {
  PLAYING,
  STOPPED,
  PAUSED,
  RESTART,
}

const int BUF_SIZE = 4096;
const String DMFOUT = "d/M/y";
const String TMFOUT = "HH:mm:ss";

String getDateString(DateTime? dt) {
  if (dt == null) return "";
  return DateFormat(DMFOUT).format(dt.toLocal());
}

String getTimeString(DateTime? dt) {
  if (dt == null) return "";
  return DateFormat(TMFOUT).format(dt.toLocal());
}

String getDateTimeString(DateTime? dt) {
  if (dt == null) return "";
  return "${getDateString(dt)} ${getTimeString(dt)}";
}

class PlayerVorbis extends StatefulWidget {
  final String fname;
  final StreamController<Duration>? playPosController;

  const PlayerVorbis(
      {Key? key, required this.fname, required this.playPosController})
      : super(key: key);

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<PlayerVorbis> {
  Duration? _duration;
  StreamSubscription? _audioStateSubscription;
  RandomAccessFile? _file;
  int _length = -1;
  int _posAudio = -1;
  PlayerVorbisMode _state = PlayerVorbisMode.STOPPED;
  double _percent = 0;
  double _start = 0;
  bool _isInAsyncCall = false;
  final _offsets = <int, int>{};
  final DateTime _data = DateTime.now();
  String _playerTxt = "";
  int _samples = -1;
  int _samplerate = -1;
  int _nchannel = -1;

  get isPlaying => audioPlugin.audioState == AudioPlayerState.PLAYING;
  get isStopped => audioPlugin.isCompleted || audioPlugin.isStopped;
  get hasBytesToRead => _posAudio * BUF_SIZE < _length;

  @override
  void initState() {
    print("init vorbis");
    super.initState();
    setState(() {
      _isInAsyncCall = true;
    });
    try {
      Uint8List bytes = File(widget.fname).readAsBytesSync();
      List<int> list = Vorbis.getSamples(bytes, _offsets);
      _samples = list[0];
      _samplerate = list[1];
      _nchannel = list[2];
      FLog.info(
          className: "PlayerVorbis",
          methodName: "InitState",
          text:
              "Samples $_samples samplerate $_samplerate channels $_nchannel offsets ${_offsets.keys.length}");
      audioPlugin.setSubscriptionDuration(.5);
      _file = File(widget.fname).openSync();
      _length = _file!.lengthSync();
      _duration = Duration(seconds: _samples ~/ _samplerate);
      _playerTxt = "${getDateTimeString(_data)} - ${_printDuration(_duration)}";
    } catch (ex) {
      FLog.error(
        className: "PlayerVorbis",
        methodName: "InitState",
        text: "Error $ex",
      );
    }
    start();
    setState(() {
      _isInAsyncCall = false;
    });
  }

  @override
  void dispose() {
    print("dispose vorbis");
    _audioStateSubscription?.cancel();
    audioPlugin.stop();
    _file?.close();
    _file = null;
    super.dispose();
  }

  String _printDuration(Duration? duration) {
    String twoDigits(int n) {
      if (n >= 10) return "$n";
      return "0$n";
    }

    if (duration == null) return "";
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Duration _calc(double pos) {
    return Duration(
        milliseconds: ((_duration != null ? _duration!.inMilliseconds : 0.0) *
                pos.clamp(0.0, 1.0))
            .round());
  }

  Future<void> stop() async {
    print("Inizio stop");
    setState(() {
      _isInAsyncCall = _state == PlayerVorbisMode.PLAYING;
      _state = PlayerVorbisMode.STOPPED;
      _start = 0;
      _percent = 0;
      _playerTxt = "${getDateTimeString(_data)} - ${_printDuration(_duration)}";
    });
  }

  Future<void> pause() async {
    print("Inizio pause");
    setState(() {
      _isInAsyncCall = true;
      _state = PlayerVorbisMode.PAUSED;
      _start = _start + _percent;
      _percent = 0;
    });
  }

  Future<void> start() async {
    _state = PlayerVorbisMode.PLAYING;
    _doAudioDecode(_start + _percent);
  }

  Future<Uint8List> _slice(int i, int n) async {
    if (_file == null) return Uint8List(0);
    await _file!.setPosition(BUF_SIZE * i);
    return (await _file!.read(BUF_SIZE * n));
  }

  static int _getOffsetVal(Map<int, int> offsets, int val) {
    int retval = 0;
    var sortedKeys = offsets.keys.toList()..sort();
    for (int key in sortedKeys) {
      if (key < val) {
        retval = offsets[key]!;
      } else {
        break;
      }
    }
    return retval;
  }

  int _getAudioOffset(double pos, int nc) {
    int samples = (pos * _samples).round();
    int offsetPcm = _getOffsetVal(_offsets, samples);
    int posAudio = offsetPcm ~/ BUF_SIZE;
    print("_getAudioOffset posAudio $posAudio");
    return posAudio;
  }

  void _listener(int? p) {
    if (p != null) {
      if (mounted && _state == PlayerVorbisMode.PLAYING) {
        _percent = Duration(milliseconds: p).inMilliseconds /
            _duration!.inMilliseconds;
        Duration durata = _calc(_start + _percent);
        DateTime date = _data.add(durata);
        setState(() {
          _playerTxt = "${getDateTimeString(date)} - ${_printDuration(durata)}";
        });
        widget.playPosController?.add(durata);
      }
    } else if (audioPlugin.isCompleted) {
      if (_state != PlayerVorbisMode.PAUSED) {
        FLog.info(
            className: "PlayerVorbis",
            methodName: "InitState",
            text: "Arrivato onCompleted");
        setState(() {
          _state = PlayerVorbisMode.STOPPED;
          _start = 0;
          _percent = 0;
          _playerTxt =
              "${getDateTimeString(_data)} - ${_printDuration(_duration)}";
          _isInAsyncCall = false;
        });
      } else {
        setState(() {
          _isInAsyncCall = false;
        });
      }
    }
  }

  Future<void> _doAudioDecode(double pos) async {
    bool ended = false;
    int queue = 0;
    _posAudio = _getAudioOffset(pos, _nchannel);
    FLog.info(
        className: "PlayerVorbis",
        methodName: "_doAudioDownload",
        text: "Start posAudio $_posAudio");
    await audioPlugin.init(_samplerate, _nchannel, vb: true);
    _audioStateSubscription = audioPlugin.onAudioStateChanged.listen(_listener);
    await audioPlugin.write(await _slice(0, 4), play: _posAudio == 0); //header
    if (_posAudio == 0) _posAudio += 4;
    if (hasBytesToRead) {
      //gioco dei tre buffer
      await audioPlugin.write(await _slice(_posAudio, 3));
      _posAudio += 3;
    }
    await audioPlugin.play();
    while ((_state == PlayerVorbisMode.PLAYING ||
        _state == PlayerVorbisMode.RESTART)) {
      if (_state == PlayerVorbisMode.RESTART) {
        ended = false;
        await audioPlugin.clear();
        setState(() {
          _state = PlayerVorbisMode.PLAYING;
          _posAudio = _getAudioOffset(_start, _nchannel);
          _isInAsyncCall = false;
        });
      }
      if (hasBytesToRead) {
        await audioPlugin.write(await _slice(_posAudio++, 1));
      } else {
        if (!ended) {
          ended = true;
          await audioPlugin.write(Uint8List(0));
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }
      // while (_state == PlayerVorbisMode.PLAYING &&
      //     (queue = await audioPlugin.queueLen()) > 9) {
      //   await Future.delayed(const Duration(milliseconds: 200));
      // }
      print(
          "_doAudioDownload ${DateTime.now()} posAudio $_posAudio $queue $ended");
    }
    if (!ended) await audioPlugin.write(Uint8List(0));
    if (_state == PlayerVorbisMode.STOPPED ||
        _state == PlayerVorbisMode.PAUSED) {
      await audioPlugin.stop();
    }
    FLog.info(
        className: "PlayerVorbis",
        methodName: "_doAudioDownload",
        text: "Finish");
  }

  onPausePlayerPressed() {
    //print("onPausePlayerPressed");
    return isPlaying ? pause : null;
  }

  onStartPlayerPressed() {
    //print("onStartPlayerPressed");
    return isStopped ? start : null;
  }

  @override
  Widget build(BuildContext context) {
    print("Build $_percent $_start");
    final Size logicalSize = MediaQuery.of(context).size;
    double _width = logicalSize.width;

    final topAppBar = AppBar(
      title: Text("Vorbis"),
    );

    return Scaffold(
      appBar: topAppBar,
      body: Container(
        width: _width,
        height: 140.0,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18.0), topRight: Radius.circular(18.0)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 8.0,
              color: Color.fromRGBO(0, 0, 0, 0.25),
            )
          ],
        ),
        child: _isInAsyncCall
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: isStopped
                            ? onStartPlayerPressed()
                            : onPausePlayerPressed(),
                        padding: EdgeInsets.all(8.0),
                        icon: ImageIcon(AssetImage(isStopped
                            ? "images/play_circle_outline_black_48dp.png"
                            : "images/pause_circle_outline_black_48dp.png")),
                      ),
                      IconButton(
                        onPressed: stop,
                        padding: EdgeInsets.all(8.0),
                        icon:
                            ImageIcon(AssetImage("images/stop_black_48dp.png")),
                      ),
                      Container(
                        margin: EdgeInsets.only(
                            left: 8.0, right: 8.0, top: 12.0, bottom: 16.0),
                        child: Text(
                          _playerTxt,
                          style: TextStyle(fontSize: 20.0),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      PositionedTapDetector2(
                          onTap: (TapPosition position) async {
                            if (isStopped) return;
                            double pos = (position.relative!.dx / _width)
                                .clamp(0.0, 1.0);
                            print('Audio_play percentage $pos');
                            setState(() {
                              _isInAsyncCall = true;
                              _state = PlayerVorbisMode.RESTART;
                              _start = pos;
                            });
                          },
                          child: CustomSlider(
                              width: _width,
                              height: 60.0,
                              percent: (_start + _percent).clamp(0.0, 1.0),
                              oscillo: null)),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class CustomSlider extends StatelessWidget {
  final double width;
  final double height;
  final double percent;
  final List<List<double>>? oscillo;

  CustomSlider(
      {required this.width,
      required this.height,
      required this.percent,
      required this.oscillo});

  @override
  Widget build(BuildContext context) {
    //print("Percentage $percentage");
    return Container(
        width: width,
        height: height,
        child: CustomPaint(painter: _Sky(percent)));
  }
}

class _Sky extends CustomPainter {
  final double percent;
  Paint mBluePaint = Paint()
    ..strokeWidth = 2.0
    ..color = Colors.blue;
  Paint mGrayPaint = Paint()
    ..strokeWidth = 2.0
    ..color = Colors.blue.withAlpha(0x4C);
  Paint mRedPaint = Paint()
    ..strokeWidth = 2
    ..color = Colors.purple;
  Paint mRectPaint = Paint()..color = Colors.transparent;

  _Sky(this.percent);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height == 0) return;
    canvas.drawRect(
        Rect.fromLTRB(0.0, 0.0, percent * size.width, size.height), mGrayPaint);
    canvas.drawLine(Offset(percent * size.width, 0),
        Offset(percent * size.width, size.height), mRedPaint);
  }

  @override
  bool shouldRepaint(_Sky oldDelegate) {
    return true;
  }
}
