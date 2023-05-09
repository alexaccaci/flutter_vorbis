import 'dart:convert';
import 'dart:typed_data';
import 'ogg.dart';
import 'info.dart';
import 'comment.dart';
import 'dspstate.dart';
import 'block.dart';

class Vorbis {
  late SyncState oy;
  late StreamState os;
  late Page og; // Ogg bitstream
  late Packet op;
  late Info vi;
  late Comment vc;
  late DspState vd;
  late Block vb;
  List<List<List<double>>> pcmInfo = [];
  List<int> pcmIndex = [];
  int num_headers = 0;
  Uint8List bufferConv = Uint8List(1024 * 1024);
  Uint8List bufferRest = Uint8List(0);
  Uint8List bufferSlice = Uint8List(100 * 1024);
  int packet = 0;
  int written = 0;

  Vorbis() {
    num_headers = 0;
    packet = 0;
    written = 0;
    op = new Packet();
    og = new Page();
    os = new StreamState();
    oy = new SyncState();

    vd = new DspState();
    vb = new Block(vd);
    vc = new Comment();
    vi = new Info();

    //joggSyncState.init();
    vi.init();
    vc.init();
  }

  void clean() {
    os.clear();
    vb.clear();
    vd.clear();
    vi.clear();
    oy.clear();
    print("Done cleaning up.");
  }

  int _readPage(Uint8List buffer_in, int size, int new_buffer) {
    int ret, index;
    int one_buffer = 1;

    if (buffer_in == null) {
      print("Error allocating buffer for OGG decoding\n");
      return -1;
    }
    while (oy.pageout(og) != 1) {
      // This returns when a page is ready
      // there are not any other pages to get, it needs a new buffer
      if (new_buffer == 0) {
        return 0;
      }
      // The page require more than a single buffer
      if (one_buffer == 0) {
        return 0;
      }
      // We get the new index and an updated buffer.
      index = oy.buffer(size);
      //System.arraycopy(buff_in,0,joggSyncState.data,index,size);
      oy.data.setAll(index, buffer_in);

      ret = oy.wrote(size); //Tell libOGG how many data are in the buffer
      if (ret != 0) {
        print("Error sending data to the OGG library\n");
        return -1;
      }
      one_buffer--;
    }

    // note e' in grado di gestire un solo stream!
    //Initialize a stream, only if the BOS flag is set.
    //printBytes(og.header_base, og.header_len);
    //int x = og.bos();
    //print("bos $x ${og.header}");
    if (og.bos() != 0) {
      os.init(og.serialno());
      os.reset();
    }

    // Submit page to stream
    ret = os.pagein(og);

    //System.err.println("---- Page length: %ld\n", page.header_len + page.body_len);
    //If the buffer contains more than a page, the size are summed
    //state->page_len += (int32_t)(page.header_len + page.body_len);
    if (ret != 0) {
      print("Error submitting OGG page to stream\n");
      return -1;
    }
    //print("granuepos " + joggPage.granulepos().toString());
    return 1;
  }

  int sliceBuffer(Uint8List buffer) {
    int retval = 0;
    //print("buff ${buffer.length} rest ${bufferRest.length}");
    if (buffer.length == 0)
      return _decodeBuffer(
          Uint8List.view(bufferRest.buffer, 0, bufferRest.length), retval);
    int len = bufferRest.length + buffer.length;
    bufferSlice.setAll(
        0, Uint8List.view(bufferRest.buffer, 0, bufferRest.length));
    bufferSlice.setAll(
        bufferRest.length, Uint8List.view(buffer.buffer, 0, buffer.length));
    for (int i = 0; true; i += 4096) {
      if ((len - i) >= 4096) {
        //print("Read buffer $i $retval");
        retval =
            _decodeBuffer(Uint8List.view(bufferSlice.buffer, i, 4096), retval);
      } else {
        bufferRest = new Uint8List(len - i);
        //print("Rest buffer $i ${bufferRest.length}");
        bufferRest.setAll(
            0, Uint8List.view(bufferSlice.buffer, i, bufferRest.length));
        break;
      }
    }
    return retval;
  }

  int _decodeBuffer(Uint8List buffer_in, int out_len) {
    int ret;
    int new_buffer = 1;
    int samples;

    // Read a page
    //printBytes(buffer_in, buffer_in.length);
    while ((ret = _readPage(buffer_in, buffer_in.length, new_buffer)) == 1) {
      new_buffer = 0;
      while (true) {
        // get all the packets from stream
        ret = os.packetout(op);

        // Il primo pacchetto dati ha un numero di pagina > 4; questo fa
        // si che la libOgg generi un out of sync che pero' puo' essere recuperato
        if (ret == -1) {
          print("Warning recovering 1st packet!\n");
          ret = os.packetout(op);
        }

        if (ret == 0) {
          // Need more data to be able to complete the packet
          break;
        } else if (ret == -1) {
          // We are out of sync and there is a gap in the data.
          // We lost a page somewhere.
          print("Warning out of sync\n");
          return -1;
          //break;
        }
        // DECODE  vorbis packet!
        if (num_headers < 3) {
          // header packet
          num_headers++;
          ret = vi.synthesis_headerin(vc, op);
          if (ret == -1) {
            print("Error parsing header not Vorbis\n");
            return -1;
          }
          if (num_headers == 3) {
            print("\nBitstream is ${vi.channels} channel, ${vi.rate} Hz");
            var vendor = utf8.decode(vc.vendor!);
            print("Encoded by: $vendor\n");

            vd.synthesis_init(vi);
            vb.init(vd);
            pcmInfo = List.generate(1, (_) => []);
            pcmIndex = List.filled(vi.channels, 0);
          }
        } else {
          // data packet
          //print("granulepos "+og.granulepos().toString());
          if (vb.synthesis(op) == 0) {
            vd.synthesis_blockin(vb);
          }

          while ((samples = vd.synthesis_pcmout(pcmInfo, pcmIndex)) > 0) {
            packet++;
            for (int i = 0; i < vi.channels; i++) {
              for (int j = 0; j < samples; j++) {
                int value = (pcmInfo[0][i][pcmIndex[i] + j] * 32767).round();
                if (value > 32767) value = 32767;
                if (value < -32768) value = -32768;
                if (value < 0) value = value | 0x8000;
                bufferConv[out_len + i * 2 + vi.channels * j * 2] = (value);
                bufferConv[out_len + i * 2 + vi.channels * j * 2 + 1] =
                    (value >> 8);
              }
            }
            out_len += samples * vi.channels * 2;
            written += samples * vi.channels * 2;
            // indica il numero di campioni effettivamente letti, puo' essere utile per gestire le dimensioni dei buffer
            //print("Packet $packet,$written,$samples");
            ret = vd.synthesis_read(samples);
            if (ret != 0) {
              print("Error signaling Vorbis the number of samples read\n");
              return -1;
            }
          }
        } // data packet
      } // while(1)
    } // while (read_page...
    if (ret == -1) {
      print("Error calling read_page() function\n");
      return -1;
    }
    //print("ocio "+printBytes(v.bufferConv, v.out_len));
    return out_len;
  }

  static List<int> getSamples(Uint8List data, Map<int, int> offsets) {
    int retval = 0;
    SyncState oy = new SyncState();
    StreamState os = new StreamState();
    Page og = new Page(); // Ogg bitstream
    Packet op = new Packet();
    Info vi = new Info();
    Comment vc = new Comment();
    int readed = 0;
    int bytes = 0;
    int first = -1;
    int nskip = data.length ~/ (1048576 * 3);

    while (true) {
      int eos = 0;
      bytes = _readOgg(oy, data, readed);
      readed += bytes;

      if (oy.pageout(og) != 1) {
        if (bytes < 4096) break; /*test last packet!*/
        print("Input does not appear to be an Ogg bitstream.");
        return [-1];
      }
      os.init(og.serialno());
      vi.init();
      vc.init();
      if (os.pagein(og) < 0) {
        print("Error reading first page of Ogg bitstream data.");
        return [-2];
      }

      if (os.packetout(op) != 1) {
        print("Error reading initial header of Ogg bitstream data.");
        return [-3];
      }

      if (vi.synthesis_headerin(vc, op) < 0) {
        print("This Ogg bitstream does not contain Vorbis audio data.");
        return [-4];
      }

      while (eos == 0) {
        while (eos == 0) {
          int result = oy.pageout(og);
          if (result == 0) break; // need more data
          if (result == -1) {
            print("Corrupt or missing data in bitstream; continuing...");
            //first = -1;
          } else {
            if (first < 0) first = og.granulepos();
            retval = og.granulepos();
            print("granulepos $readed $retval");
            offsets[retval - first] = readed;
            os.pagein(og);
            if (og.eos() != 0) eos = 1;
            if (readed + nskip * 4096 < data.length) readed += nskip * 4096;
          }
        }
        if (eos == 0) {
          bytes = _readOgg(oy, data, readed);
          readed += bytes;
          if (bytes == 0) eos = 1;
        }
      }
      os.clear();
    }
// OK, clean up the framer
    oy.clear();
    return [retval - first, vi.rate, vi.channels];
  }

  static int _readOgg(SyncState oy, Uint8List data, int readed) {
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
}

printBytes(Uint8List msg, int len) {
  String retval = "";
  for (int i = 0; i < len; i++)
    retval += msg[i].toRadixString(16).padLeft(2, '0').toUpperCase();
  print(retval);
}
