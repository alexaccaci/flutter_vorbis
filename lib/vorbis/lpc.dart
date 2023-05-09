import 'drft.dart';
import 'dart:math';

class Lpc {
  // en/decode lookups
  Drft fft = new Drft();

  int ln = 0;
  int m = 0;

  static double lpc_from_data(
      List<double> data, List<double> lpc, int n, int m) {
    List<double> aut = List.filled(m + 1, 0);
    double error;
    int i, j;

    // autocorrelation, p+1 lag coefficients

    j = m + 1;
    while (j-- != 0) {
      double d = 0;
      for (i = j; i < n; i++) d += data[i] * data[i - j];
      aut[j] = d;
    }

    // Generate lpc coefficients from autocorr values

    error = aut[0];
    /*
    if(error==0){
      for(int k=0; k<m; k++) lpc[k]=0.0f;
      return 0;
    }
    */

    for (i = 0; i < m; i++) {
      double r = -aut[i + 1];

      if (error == 0) {
        for (int k = 0; k < m; k++) lpc[k] = 0.0;
        return 0;
      }

      for (j = 0; j < i; j++) r -= lpc[j] * aut[i - j];
      r /= error;

      // Update LPC coefficients and total error

      lpc[i] = r;
      for (j = 0; j < i / 2; j++) {
        double tmp = lpc[j];
        lpc[j] += r * lpc[i - 1 - j];
        lpc[i - 1 - j] += r * tmp;
      }
      if (i % 2 != 0) lpc[j] += lpc[j] * r;

      error *= 1.0 - r * r;
    }

    return error;
  }

  double lpc_from_curve(List<double> curve, List<double> lpc) {
    int n = ln;
    List<double> work = List.filled(n + n, 0);
    double fscale = (0.5 / n);
    int i, j;

    for (i = 0; i < n; i++) {
      work[i * 2] = curve[i] * fscale;
      work[i * 2 + 1] = 0;
    }
    work[n * 2 - 1] = curve[n - 1] * fscale;

    n *= 2;
    fft.backward(work);

    i = 0;
    for (j = n ~/ 2; i < n / 2;) {
      double temp = work[i];
      work[i++] = work[j];
      work[j++] = temp;
    }

    return (lpc_from_data(work, lpc, n, m));
  }

  void init(int mapped, int m) {
    ln = mapped;
    this.m = m;

    // we cheat decoding the LPC spectrum via FFTs
    fft.init(mapped * 2);
  }

  void clear() {
    fft.clear();
  }

  static double FAST_HYPOT(double a, double b) {
    return sqrt((a) * (a) + (b) * (b));
  }

  void lpc_to_curve(List<double> curve, List<double> lpc, double amp) {
    for (int i = 0; i < ln * 2; i++) curve[i] = 0.0;

    if (amp == 0) return;

    for (int i = 0; i < m; i++) {
      curve[i * 2 + 1] = lpc[i] / (4 * amp);
      curve[i * 2 + 2] = -lpc[i] / (4 * amp);
    }

    fft.backward(curve);

    {
      int l2 = ln * 2;
      double unit = 1.0 / amp;
      curve[0] = (1.0 / (curve[0] * 2 + unit));
      for (int i = 1; i < ln; i++) {
        double real = (curve[i] + curve[l2 - i]);
        double imag = (curve[i] - curve[l2 - i]);

        double a = real + unit;
        curve[i] = (1.0 / FAST_HYPOT(a, imag));
      }
    }
  }
}
