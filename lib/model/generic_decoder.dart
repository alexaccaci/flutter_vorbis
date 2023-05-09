import 'dart:typed_data';
import 'dart:convert';

class GenericDecoder {
  late Uint8List data;
  int o = 0;

  GenericDecoder(Uint8List data) {
    this.data = data;
  }

  static int staticReadInt(Uint8List data, int start, int len) {
    int r = 0;
    for (int i = 0; i < len; i++) {
      r |= data[start + i] << (i << 3);
    }
    return r;
  }

  int readIntBE(int len) {
    int r = 0;
    for (int i = 0; i < len; ++i) {
      r |= this.data[this.o + (len - 1 - i)] << (i << 3);
    }
    this.o += len;
    return r;
  }

  int readInt(int len) {
    int r = 0;
    for (int i = 0; i < len; ++i) {
      r |= this.data[this.o + i] << (i << 3);
    }
    this.o += len;
    return r;
  }

  int readSignedInt(int len) {
    int r = readInt(len);
    int mask = 1 << (8 * len - 1);
    if ((mask & r) != 0) {
      mask = (mask << 1) - 1;
      // This is a negative number.  Invert the bits and add 1
      r = (~r & mask) + 1;
      // Add a negative sign
      r = -r;
    }
    return r;
  }

  double readFloat32() {
    ByteData bytes = readBytes(4).buffer.asByteData();
    return bytes.getFloat32(0);
  }

  bool readBoolean() {
    return this.data[this.o++] == 1;
  }

  String readString(int len) {
    var list = new Uint8List.fromList(Uint8List.view(data.buffer, o, len));
    String ret = utf8.decode(list);
    this.o += len;
    return ret;
  }

  String readLenString(int lenLen) {
    int len = this.readInt(lenLen);
    return this.readString(len);
  }

  Uint8List readBytes(int len) {
    Uint8List ret = Uint8List.fromList(Uint8List.view(data.buffer, o, len));
    this.o += len;
    return ret;
  }

  int available() {
    return this.data.lengthInBytes - this.o;
  }

  bool hasMoreData() {
    return this.available() > 0;
  }

  int getCurrentOffset() {
    return this.o;
  }

  int readByte() {
    return this.data[this.o++];
  }

  void skip(int i) {
    this.o += i;
  }

  static Uint8List buildFromNibble(String hexString) {
    int len = (hexString.length / 2).floor();
    Uint8List data = Uint8List(len);
    for (int i = 0; i < len; i++) {
      final bytes = hexString.substring(i * 2, (i + 1) * 2);
      int val = int.parse(bytes, radix: 16);
      data[i] = val;
    }
    return data;
  }
}
