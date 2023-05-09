import 'dart:async';

import 'package:flutter/material.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart';

import 'audio_plugin.dart';
import 'pcmoscillo.dart';

class PlayerAudio extends StatefulWidget {
  final String fname;
  final StreamController<Duration>? playPosController;

  PlayerAudio({Key? key, required this.fname, required this.playPosController})
      : super(key: key);

  @override
  PlayerAudioState createState() => PlayerAudioState();
}

class PlayerAudioState extends State<PlayerAudio> {
  StreamSubscription? _playerSubscription;
  bool get isPlaying =>
      audioPlugin.isPlaying ||
      audioPlugin.isPaused;
  bool get isStopped => audioPlugin.isStopped;
  bool get isPaused => audioPlugin.isPaused;
  String? _playerTxt;

  double sliderCurrentPosition = 0.0;
  double maxDuration = 1.0;

  @override
  void initState() {
    super.initState();
    print("Samplerate 44100 channels 2");
    _playerTxt = "00:00";
    audioPlugin.setSubscriptionDuration(.5);
  }

  @override
  void dispose() {
    if (isPlaying) stop();
    super.dispose();
  }

  String printMmSs(Duration? duration) {
    String twoDigits(int n) {
      if (n >= 10) return "$n";
      return "0$n";
    }

    if (duration == null) return "";
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> start() async {
    try {
      if (widget.fname == null) {
        print('Error starting player fname null');
        return;
      }
      String? path = await audioPlugin.startPlayer(widget.fname);
      if (path == null) {
        print('Error starting player path null');
        return;
      }
      print('startPlayer: $path');
      await audioPlugin.setVolume(1.0);

      _playerSubscription = audioPlugin.onPlayerStateChanged.listen((e) {
        if (e != null) {
          sliderCurrentPosition = e.currentPosition;
          maxDuration = e.duration;
          //print("Current Position $sliderCurrentPosition $maxDuration");
          Duration durata = Duration(milliseconds: e.currentPosition.toInt());
          if (mounted) {
            if (widget.playPosController != null)
              widget.playPosController!.add(durata);
            setState(() {
              _playerTxt = printMmSs(durata);
            });
          }
        }
      });
    } catch (err) {
      print('Error starting player $err');
    }
    setState(() {});
  }

  Future<void> stop() async {
    try {
      String? result = await audioPlugin.stopPlayer();
      print(
        'stopPlayer: $result',
      );
      if (_playerSubscription != null) {
        _playerSubscription!.cancel();
        _playerSubscription = null;
      }
      sliderCurrentPosition = 0.0;
      _playerTxt = "00:00";
      if (widget.playPosController != null) {
        widget.playPosController!.add(Duration(milliseconds: 0));
      }
    } catch (err) {
      print('Error stopPlayer: $err');
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> pause() async {
    String? result;
    try {
      if (isPaused) {
        result = await audioPlugin.resumePlayer();
        print('resumePlayer: $result');
      } else {
        result = await audioPlugin.pausePlayer();
        print('pausePlayer: $result');
      }
    } catch (err) {
      print('Error pausePlayer: $err');
    }
    setState(() {});
  }

  void seekToPlayer(int milliSecs) async {
    String? result = await audioPlugin.seekToPlayer(milliSecs);
    print('seekToPlayer: $result');
  }

  onPausePlayerPressed() {
    return isPlaying ? pause : null;
  }

  onStopPlayerPressed() {
    return isPlaying ? stop : null;
  }

  onStartPlayerPressed() {
    return isStopped ? start : null;
  }

  @override
  Widget build(BuildContext context) {
    final Size logicalSize = MediaQuery.of(context).size;
    double _width = logicalSize.width;

    final topAppBar = AppBar(
      title: Text("Opus"),
    );
    return Scaffold(
        appBar: topAppBar,
        body: Container(
      width: _width,
      height: 140.0,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18.0), topRight: Radius.circular(18.0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 8.0,
            color: Color.fromRGBO(0, 0, 0, 0.25),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: isStopped
                    ? onStartPlayerPressed()
                    : onPausePlayerPressed(),
                padding: EdgeInsets.all(8.0),
                icon: ImageIcon(AssetImage(isStopped || isPaused
                    ? "images/play_circle_outline_black_48dp.png"
                    : "images/pause_circle_outline_black_48dp.png")),
              ),
              IconButton(
                onPressed: onStopPlayerPressed(),
                padding: EdgeInsets.all(8.0),
                icon: ImageIcon(AssetImage("images/stop_black_48dp.png")),
              ),
              Container(
                margin: EdgeInsets.only(
                    left: 8.0, right: 8.0, top: 12.0, bottom: 16.0),
                child: Text(
                  this._playerTxt!,
                  style: TextStyle(fontSize: 20.0),
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              PositionedTapDetector2(
                  onTap: (TapPosition position) async {
                    if (isStopped) return;
                    double pos =
                        (position.relative!.dx / _width).clamp(0.0, 1.0) *
                            maxDuration;
                    print('Audio_play percentage $pos');
                    await audioPlugin.seekToPlayer(pos.toInt());
                  },
                  child: CustomSlider(
                      width: _width,
                      height: 60.0,
                      percent:
                          (sliderCurrentPosition / maxDuration).clamp(0.0, 1.0),
                      oscillo: null)),
            ],
          ),
        ],
      ),
    ));
  }
}

class CustomSlider extends StatelessWidget {
  final double width;
  final double height;
  final double percent;
  final List<List<double>>? oscillo;

  CustomSlider({required this.width, required this.height, required this.percent, required this.oscillo});

  @override
  Widget build(BuildContext context) {
    //print("Percentage $percentage");
    return Container(
        width: width,
        height: height,
        child: CustomPaint(painter: Oscillo(width, height, percent, oscillo)));
  }
}
