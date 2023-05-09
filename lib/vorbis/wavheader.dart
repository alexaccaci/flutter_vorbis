import 'dart:typed_data';
import 'dart:math';

const int WAVHEADERLEN = 44;

class WavHeader {
  static int writeUIntLE(int value, Uint8List buf, int indice) {
    buf[indice++] = (value & 0xFF);
    buf[indice++] = (value >> 8) & 0xff;
    buf[indice++] = (value >> 16) & 0xff;
    buf[indice++] = (value >> 24) & 0xff;
    return 4;
  }

  static int writeUShortLE(int value, Uint8List buf, int indice) {
    buf[indice++] = (value & 0xFF);
    buf[indice++] = (value >> 8) & 0xff;
    return 2;
  }

  static int writeUInt(int value, Uint8List buf, int indice) {
    buf[indice++] = (value >> 24) & 0xff;
    buf[indice++] = (value >> 16) & 0xff;
    buf[indice++] = (value >> 8) & 0xff;
    buf[indice++] = (value & 0xFF);
    return 4;
  }

  static int readUShortLE(Uint8List buf, int indice) {
    return buf[indice] + (buf[indice + 1] << 8);
  }

  static int readUnsignedIntLE(Uint8List buf, int i) {
    return buf[i] + (buf[i+1] << 8) + (buf[i+2] << 16) + (buf[i+3] << 24);
  }

  static Uint8List getHeader(
      int len, int channels, int samplerate, int bitspersample) {
    Uint8List header = new Uint8List(WAVHEADERLEN);
    int readed = 0;
    int byterate = samplerate * channels * bitspersample ~/ 8;
    int blockalign = channels * bitspersample ~/ 8;
    readed += writeUInt(0x52494646, header, readed); //RIFF
    // Write the length of this RIFF thing.
    readed += writeUIntLE(max(len - 8, 0), header, readed);
    readed += writeUInt(0x57415645, header, readed); //WAVE
    readed += writeUInt(0x666D7420, header, readed); //fmt
    readed += writeUIntLE(16, header, readed); //subchunk1size
    readed += writeUShortLE(1, header, readed); //waveformat 1 PCM
    readed += writeUShortLE(channels, header, readed);
    readed += writeUIntLE(samplerate, header, readed);
    readed += writeUIntLE(byterate, header, readed);
    readed += writeUShortLE(blockalign, header, readed);
    readed += writeUShortLE(bitspersample, header, readed);
    readed += writeUInt(0x64617461, header, readed); //data
    readed += writeUIntLE(max(len - readed, 0), header, readed); //subchunk2size
    print("getWAVHeader $len readed $readed");
    return header;
  }

  static List<int> getSamples(Uint8List data) {
    int channels = 1;
    int bytespersample = 1;
    int samplerate = 0;
    int i = 0;
    if (data[i] != 'R'.codeUnits.first &&
        data[i + 1] != 'I'.codeUnits.first &&
        data[i + 2] != 'F'.codeUnits.first &&
        data[i + 3] != 'F'.codeUnits.first) return [-1];
    i += 4;
    while (++i < data.length - 4) {
      if (data[i] == 'f'.codeUnits.first &&
          data[i + 1] == 'm'.codeUnits.first &&
          data[i + 2] == 't'.codeUnits.first &&
          data[i + 3] == ' '.codeUnits.first) {
        channels = readUShortLE(data, i + 10);
        samplerate = readUnsignedIntLE(data, i + 12);
        bytespersample = readUShortLE(data, i + 22) ~/ 8;
      } else if (data[i] == 'd'.codeUnits.first &&
          data[i + 1] == 'a'.codeUnits.first &&
          data[i + 2] == 't'.codeUnits.first &&
          data[i + 3] == 'a'.codeUnits.first)
        return [
          (data.length - i - 8) ~/ channels ~/ bytespersample,
          samplerate,
          channels
        ];
    }
    return [-1];
  }
}
