import 'package:f_logs/model/flog/flog.dart';
import 'package:f_logs/utils/formatter/field_name.dart';
import 'package:f_logs/utils/formatter/formate_type.dart';
import 'package:f_logs/utils/timestamp/timestamp_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'model/audio_opus.dart';
import 'model/audio_vorbis.dart';


//const String FNAME = "a.opus";
//const String FNAME = "audio.ogg";
//const String FNAME = "audio1.ogg";
//const String FNAME = "file.ogg";
//const String FNAME = "file7.ogg";
//const String FNAME = "dev.ogg";
//const String FNAME = "radio.ogg";
const String FNAME = "rondo.ogg";
//const String FNAME = "rondo.wav";

printBytes(Uint8List msg, int len) {
  String retval = "";
  for (int i = 0; i < len; i++)
    retval += msg[i].toRadixString(16).padLeft(2, '0').toUpperCase();
  print(retval);
}

Future<File> copyFileAudio(String fname) async {
  final file = File('${(await getTemporaryDirectory()).path}/tmp.opus');
  bool exists = await file.exists();
  if (exists) await file.delete(recursive: true);
  await file.create(recursive: true);
  Uint8List bytes =
      (await rootBundle.load('assets/$fname')).buffer.asUint8List();
  await file.writeAsBytes(bytes);
  return file;
}

Uint8List desliceFile(List<Uint8List> list) {
  Uint8List retval = Uint8List(0);
  for (Uint8List item in list) retval = Uint8List.fromList(retval + item);
  return retval;
}

Future<List<Uint8List>> sliceFile(File file) async {
  const int BUF_SIZE = 4096;
  bool isVorbis = file.path.endsWith('ogg');
  List<Uint8List> retval = [];
  int len = await file.length();
  int size = isVorbis ? BUF_SIZE : 4 * BUF_SIZE;
  for (int i = 0; i * size < len; i++) {
    List<int> list =
    (await file.openRead(size * i, size * (i + 1)).toList())[0];
    retval.add(Uint8List.fromList(list));
  }
  return retval;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  File file = await copyFileAudio(FNAME);
  final config = FLog.getDefaultConfigurations()
    ..isDevelopmentDebuggingEnabled = true
    ..formatType = FormatType.FORMAT_CUSTOM
    ..fieldOrderFormatCustom = [
      FieldName.TIMESTAMP,
      FieldName.CLASSNAME,
      FieldName.METHOD_NAME,
      FieldName.TEXT,
      FieldName.EXCEPTION,
      FieldName.LOG_LEVEL,
      FieldName.STACKTRACE
    ] // Field order for output
    ..timestampFormat = TimestampFormat.TIME_FORMAT_FULL_3
    ..customOpeningDivider = ""
    ..customClosingDivider = "";
  FLog.applyConfigurations(config);

  runApp(MyApp(file.path));
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  final String fname;

  MyApp(this.fname);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PlayerVorbis(fname: fname, playPosController: null,),
    );
  }
}
