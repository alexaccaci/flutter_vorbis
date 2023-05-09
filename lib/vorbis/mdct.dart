import 'dart:math';

class Mdct {
  int n = 0;
  int log2n = 0;

  List<double>? trig;
  List<int>? bitrev;

  double scale = 0;

  void init(int n) {
    bitrev = List.filled(n ~/ 4, 0);
    trig = List.filled(n + n ~/ 4, 0);

    log2n = (log(n) / log(2)).round();
    this.n = n;

    int AE = 0;
    int AO = 1;
    int BE = AE + n ~/ 2;
    int BO = BE + 1;
    int CE = BE + n ~/ 2;
    int CO = CE + 1;
    // trig lookups...
    for (int i = 0; i < n / 4; i++) {
      trig![AE + i * 2] = cos((pi / n) * (4 * i));
      trig![AO + i * 2] = -sin((pi / n) * (4 * i));
      trig![BE + i * 2] = cos((pi / (2 * n)) * (2 * i + 1));
      trig![BO + i * 2] = sin((pi / (2 * n)) * (2 * i + 1));
    }
    for (int i = 0; i < n / 8; i++) {
      trig![CE + i * 2] = cos((pi / n) * (4 * i + 2));
      trig![CO + i * 2] = -sin((pi / n) * (4 * i + 2));
    }

    {
      int mask = (1 << (log2n - 1)) - 1;
      int msb = 1 << (log2n - 2);
      for (int i = 0; i < n / 8; i++) {
        int acc = 0;
        for (int j = 0; msb >> j != 0; j++)
          if (((msb >> j) & i) != 0) acc |= 1 << j;
        bitrev![i * 2] = ((~acc) & mask);
        //	bitrev[i*2]=((~acc)&mask)-1;
        bitrev![i * 2 + 1] = acc;
      }
    }
    scale = 4.0 / n;
  }

  void clear() {}

  void forward(List<double> inn, List<double> out) {}

  List<double> _x = List.filled(1024, 0);
  List<double> _w = List.filled(1024, 0);

  //synchronized
  void backward(List<double> inn, List<double> out) {
    if (_x.length < n / 2) {
      _x = List.filled(n ~/ 2, 0);
    }
    if (_w.length < n / 2) {
      _w = List.filled(n ~/ 2, 0);
    }
    var x = _x;
    var w = _w;
    int n2 = n >> 1;
    int n4 = n >> 2;
    int n8 = n >> 3;

    // rotate + step 1
    {
      int inO = 1;
      int xO = 0;
      int A = n2;

      int i;
      for (i = 0; i < n8; i++) {
        A -= 2;
        x[xO++] = -inn[inO + 2] * trig![A + 1] - inn[inO] * trig![A];
        x[xO++] = inn[inO] * trig![A + 1] - inn[inO + 2] * trig![A];
        inO += 4;
      }

      inO = n2 - 4;

      for (i = 0; i < n8; i++) {
        A -= 2;
        x[xO++] = inn[inO] * trig![A + 1] + inn[inO + 2] * trig![A];
        x[xO++] = inn[inO] * trig![A] - inn[inO + 2] * trig![A + 1];
        inO -= 4;
      }
    }

    var xxx = mdct_kernel(x, w, n, n2, n4, n8);
    int xx = 0;

    // step 8

    {
      int B = n2;
      int o1 = n4, o2 = o1 - 1;
      int o3 = n4 + n2, o4 = o3 - 1;

      for (int i = 0; i < n4; i++) {
        double temp1 = (xxx[xx] * trig![B + 1] - xxx[xx + 1] * trig![B]);
        double temp2 = -(xxx[xx] * trig![B] + xxx[xx + 1] * trig![B + 1]);

        out[o1] = -temp1;
        out[o2] = temp1;
        out[o3] = temp2;
        out[o4] = temp2;

        o1++;
        o2--;
        o3++;
        o4--;
        xx += 2;
        B += 2;
      }
    }
  }

  List<double> mdct_kernel(
      List<double> x, List<double> w, int n, int n2, int n4, int n8) {
    // step 2

    int xA = n4;
    int xB = 0;
    int w2 = n4;
    int A = n2;

    for (int i = 0; i < n4;) {
      double x0 = x[xA] - x[xB];
      double x1;
      w[w2 + i] = x[xA++] + x[xB++];

      x1 = x[xA] - x[xB];
      A -= 4;

      w[i++] = x0 * trig![A] + x1 * trig![A + 1];
      w[i] = x1 * trig![A] - x0 * trig![A + 1];

      w[w2 + i] = x[xA++] + x[xB++];
      i++;
    }

    // step 3

    {
      for (int i = 0; i < log2n - 3; i++) {
        int k0 = n >> (i + 2);
        int k1 = 1 << (i + 3);
        int wbase = n2 - 2;

        A = 0;
        List<double> temp;

        for (int r = 0; r < (k0 >> 2); r++) {
          int w1 = wbase;
          w2 = w1 - (k0 >> 1);
          double AEv = trig![A], wA;
          double AOv = trig![A + 1], wB;
          wbase -= 2;

          k0++;
          for (int s = 0; s < (2 << i); s++) {
            wB = w[w1] - w[w2];
            x[w1] = w[w1] + w[w2];

            wA = w[++w1] - w[++w2];
            x[w1] = w[w1] + w[w2];

            x[w2] = wA * AEv - wB * AOv;
            x[w2 - 1] = wB * AEv + wA * AOv;

            w1 -= k0;
            w2 -= k0;
          }
          k0--;
          A += k1;
        }

        temp = w;
        w = x;
        x = temp;
      }
    }

    // step 4, 5, 6, 7
    {
      int C = n;
      int bit = 0;
      int x1 = 0;
      int x2 = n2 - 1;

      for (int i = 0; i < n8; i++) {
        int t1 = bitrev![bit++];
        int t2 = bitrev![bit++];

        double wA = w[t1] - w[t2 + 1];
        double wB = w[t1 - 1] + w[t2];
        double wC = w[t1] + w[t2 + 1];
        double wD = w[t1 - 1] - w[t2];

        double wACE = wA * trig![C];
        double wBCE = wB * trig![C++];
        double wACO = wA * trig![C];
        double wBCO = wB * trig![C++];

        x[x1++] = (wC + wACO + wBCE) * .5;
        x[x2--] = (-wD + wBCO - wACE) * .5;
        x[x1++] = (wD + wBCO - wACE) * .5;
        x[x2--] = (wC - wACO - wBCE) * .5;
      }
    }
    return (x);
  }
}
