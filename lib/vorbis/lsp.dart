import 'lookup.dart';
import 'dart:typed_data';

class Lsp {

  static final M_PI = 3.1415926539;

  static void lsp_to_curve(List<double> curve, List<int> map, int n, int ln,
      List<double> lsp, int m, double amp, double ampoffset) {
    int i;
    double wdel = M_PI / ln;
    for (i = 0; i < m; i++)
      lsp[i] = Lookup.coslook(lsp[i]);
    int m2 = (m ~/ 2) * 2;

    i = 0;
    while (i < n) {
      int k = map[i];
      double p = .7071067812;
      double q = .7071067812;
      double w = Lookup.coslook(wdel * k);

      for (int j = 0; j < m2; j += 2) {
        q *= lsp[j] - w;
        p *= lsp[j + 1] - w;
      }

      if ((m & 1) != 0) {
        /* odd order filter; slightly assymetric */
        /* the last coefficient */
        q *= lsp[m - 1] - w;
        q *= q;
        p *= p * (1.0 - w * w);
      }
      else {
        /* even order filter; still symmetric */
        q *= q * (1.0 + w);
        p *= p * (1.0 - w);
      }

      //  q=frexp(p+q,&qexp);
      q = p + q;
      int hx = floatToIntBits(q);
      int ix = 0x7fffffff & hx;
      int qexp = 0;

      if (ix >= 0x7f800000 || (ix == 0)) {
        // 0,inf,nan
      }
      else {
        if (ix < 0x00800000) { // subnormal
          q *= 3.3554432000e+07; // 0x4c000000
          hx = floatToIntBits(q);
          ix = 0x7fffffff & hx;
          qexp = -25;
        }
        qexp += ((ix >> 23) - 126);
        hx = (hx & 0x807fffff) | 0x3f000000;
        q = intBitsToFloat(hx);
      }

      q = Lookup.fromdBlook(
          amp * Lookup.invsqlook(q) * Lookup.invsq2explook(qexp + m)
              - ampoffset);

      do {
        curve[i++] *= q;
      }
      while (i < n && map[i] == k);
    }
  }

  static int floatToIntBits(double value) {
    var bits = ByteData(4);
    bits.setFloat32(0, value, Endian.little);
    var data = bits.buffer.asUint8List();
    int r = 0;
    for (int i = 0; i < 4; i++) {
      r |= data[i] << (i << 3);
    }
    return r;
  }

  static double intBitsToFloat(int val) {
    var data = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      data[i] = val >> (i << 3);
    }
    var bits = ByteData.view(data.buffer);
    return bits.getFloat32(0, Endian.little);
  }
}

