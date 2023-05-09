import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'dart:io';
import 'ogg.dart';
import 'dart:typed_data';
import 'info.dart';
import 'comment.dart';
import 'dspstate.dart';
import 'block.dart';
import 'wavheader.dart';

Uint8List castBytes(List<int> bytes, {bool copy = false}) {
  if (bytes is Uint8List) {
    if (copy) {
      final list = new Uint8List(bytes.length);
      list.setRange(0, list.length, bytes);
      return list;
    } else {
      return bytes;
    }
  } else {
    return new Uint8List.fromList(bytes);
  }
}

int _readOgg(SyncState oy, Uint8List data, int readed) {
  int bytes = 0;
  int toRead = data.length - readed;
  int index = oy.buffer(4096);
  if (toRead > 0) {
    if (toRead > 4096)
      bytes = 4096;
    else
      bytes = toRead;
    oy.data.setAll(index, Uint8List.view(data.buffer, readed, bytes));
    //print(oy.data);
    oy.wrote(bytes);
  } else
    oy.wrote(-1);
  return bytes;
}

int _getSamples(Uint8List data) {
  int retval = 0;
  SyncState oy = new SyncState();
  StreamState os = new StreamState();
  Page og = new Page(); // Ogg bitstream
  int readed = 0;
  int bytes = 0;

  while (true) {
    int eos = 0;
    bytes = _readOgg(oy, data, readed);
    readed += bytes;

    if (oy.pageout(og) != 1) {
      if (bytes < 4096) break;
      print("Input does not appear to be an Ogg bitstream.");
      return -1;
    }
    os.init(og.serialno());
    if (os.pagein(og) < 0) {
      print("Error reading first page of Ogg bitstream data.");
      return -2;
    }

    while (eos == 0) {
      while (eos == 0) {
        int result = oy.pageout(og);
        if (result == 0) break; // need more data
        if (result == -1) {
          print("Corrupt or missing data in bitstream; continuing...");
        } else {
          retval = og.granulepos();
          //print("granulepos $retval");
          os.pagein(og);
          if (og.eos() != 0) eos = 1;
        }
      }
      if (eos == 0) {
        bytes = _readOgg(oy, data, readed);
        readed += bytes;
        if (bytes <= 0) eos = 1;
      }
    }
    os.clear();
  }
  // OK, clean up the framer
  oy.clear();
  return retval;
}

Future<String> decode(String src) async {
  String dst = path.basenameWithoutExtension(src);
  final myFile = File('${(await getTemporaryDirectory()).path}/$dst.wav');
  if (await myFile.exists()) await myFile.delete(recursive: true);
  await myFile.create(recursive: true);

  Uint8List data = File(src).readAsBytesSync();
  int nsamples = _getSamples(data);

  int convsize = 4096 * 2;
  var convbuffer = new Uint8List(convsize);

  SyncState oy = new SyncState();
  StreamState os = new StreamState();
  Page og = new Page(); // Ogg bitstream
  Packet op = new Packet();

  Info vi = new Info();
  Comment vc = new Comment();
  DspState vd = new DspState();
  Block vb = new Block(vd);

  int readed = 0;
  int bytes = 0;
  int written = 0;
  int packet = 0;

  // Decode setup
  int eos = 0;

  bytes = _readOgg(oy, data, readed);
  readed += bytes;

  if (oy.pageout(og) != 1) {
    print("Input does not appear to be an Ogg bitstream.");
    return "Input does not appear to be an Ogg bitstream.";
  }

  os.init(og.serialno());
  vi.init();
  vc.init();
  if (os.pagein(og) < 0) {
    print("Error reading first page of Ogg bitstream data.");
    return "Error reading first page of Ogg bitstream data.";
  }

  if (os.packetout(op) != 1) {
    print("Error reading initial header packet.");
    return "Error reading initial header packet.";
  }

  if (vi.synthesis_headerin(vc, op) < 0) {
    print("This Ogg bitstream does not contain Vorbis audio data.");
    return "This Ogg bitstream does not contain Vorbis audio data.";
  }

  int i = 0;
  while (i < 2) {
    while (i < 2) {
      int result = oy.pageout(og);
      if (result == 0) break; // Need more data
      if (result == 1) {
        os.pagein(og);
        while (i < 2) {
          result = os.packetout(op);
          if (result == 0) break;
          if (result == -1) {
            print("Corrupt secondary header.  Exiting.");
          }
          vi.synthesis_headerin(vc, op);
          i++;
        }
      }
    }
    bytes = _readOgg(oy, data, readed);
    readed += bytes;
    if (bytes == 0 && i < 2) {
      print("End of file before finding all Vorbis headers!");
    }
  }

  List<Uint8List> ptr = vc.user_comments!;
  for (int j = 0; j < ptr.length; j++) {
    if (ptr[j] == null) break;
    print(ptr[j]);
  }
  print("\nBitstream is ${vi.channels} channel, ${vi.rate} Hz");
  var vendor = utf8.decode(vc.vendor!);
  print("Encoded by: $vendor\n");
  Uint8List header = WavHeader.getHeader(
      2 * nsamples * vi.channels + WAVHEADERLEN, vi.channels, vi.rate, 16);
  myFile.writeAsBytesSync(header, mode: FileMode.append);
  convsize = 4096 ~/ vi.channels;

  vd.synthesis_init(vi);
  vb.init(vd);

  List<List<List<double>>> _pcm = new List.generate(1, (_) => []);
  List<int> _index = new List.generate(vi.channels, (_) => 0);
  while (eos == 0) {
    while (eos == 0) {
      int result = oy.pageout(og);
      if (result == 0) break; // need more data
      if (result == -1) {
        print("Corrupt or missing data in bitstream; continuing...");
      } else {
        print("granulepos " + og.granulepos().toString());
        os.pagein(og);
        while (true) {
          result = os.packetout(op);
          if (result == 0) break; // need more data
          if (result == -1) {
            // already complained above
          } else {
            int samples;
            if (vb.synthesis(op) == 0) {
              vd.synthesis_blockin(vb);
            }

            while ((samples = vd.synthesis_pcmout(_pcm, _index)) > 0) {
              packet++;

              List<List<double>> pcm = _pcm[0];
              int bout = (samples < convsize ? samples : convsize);

              // convert floats to signed 16 bit little endian
              for (i = 0; i < vi.channels; i++) {
                int ptr = i * 2;
                int mono = _index[i];
                for (int j = 0; j < bout; j++) {
                  int val = (pcm[i][mono + j] * 32767.0).round();
                  if (val > 32767) val = 32767;
                  if (val < -32768) val = -32768;
                  if (val < 0) val = val | 0x8000;
                  convbuffer[ptr] = (val);
                  convbuffer[ptr + 1] = (val >> 8);
                  ptr += 2 * vi.channels;
                }
              }

              written += 2 * vi.channels * bout;
              //print("$packet $written $bytes $bout");
              myFile.writeAsBytesSync(
                  Uint8List.view(convbuffer.buffer, 0, 2 * vi.channels * bout),
                  mode: FileMode.append);

              vd.synthesis_read(bout);
            }
          }
        }
        if (og.eos() != 0) eos = 1;
      }
    }
    if (eos == 0) {
      bytes = _readOgg(oy, data, readed);
      readed += bytes;
      if (bytes <= 0) eos = 1;
    }
  }

  os.clear();
  vb.clear();
  vd.clear();
  vi.clear(); // must be called last
  oy.clear();
  print("Done ${myFile.path}.");
  return myFile.path;
}
