import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'generic_decoder.dart';

class Oscillo extends CustomPainter {
  final double width;
  final double height;
  final double percent;
  List<List<double>>? values;
  Paint mBluePaint = Paint()
    ..strokeWidth = 2.0
    ..color = Colors.blue;
  Paint mRectPaint = Paint()
    ..color =  Colors.white;
  Paint mGrayPaint = Paint()
    ..isAntiAlias = false
    ..strokeWidth = 2.0
    ..color = Colors.grey;
  double mMaxL = 0;
  double mMinL = 0;
  double mMaxR = 0;
  double mMinR = 0;

  Oscillo(this.width, this.height, this.percent, this.values);

  static double mLaw(double val) {
    val = val.clamp(-1.0, 1.0);
    double sign = val.sign;
    double abs = val.abs();
    return sign * log(1 + 255 * abs) / log(256);
  }

  static double aLaw(double val) {
    val = val.clamp(-1.0, 1.0);
    double sign = val.sign;
    double abs = val.abs();
    if (abs < 1 / 87.6) return sign * 87.6 * abs / (1 + log(87.6));
    return sign * (1 + log(87.6 * abs)) / (1 + log(87.6));
  }

  static List<List<double>>? parseOsc(Uint8List buff) {
    if (buff.length < 16) return null;
    final maxPoints = 4096;
    List<List<double>> values = [];
    GenericDecoder gd = GenericDecoder(buff);
    int nChannels = gd.readIntBE(4);
    if (nChannels < 1) return null;
    int nPoints = gd.readIntBE(4);
    int passo = 1;
    int nVal = nPoints;
    List<double> mm = List.filled(2 * nChannels, 0);
    if (nPoints > maxPoints) {
      nVal = maxPoints;
      passo = nPoints ~/ maxPoints;
    }
    for (int c = 0; c < 2 * nChannels; c++) {
      values.add(List<double>.filled(nVal, 0));
      mm[c] = 0;
    }
    for (int i = 0; i < nPoints; i++) {
      for (int c = 0; c < 2 * nChannels; c++) {
        if (gd.available() > 3) {
          double val = mLaw(gd.readFloat32());
          if (c % 2 == 0)
            mm[c] = min(mm[c], val.clamp(-1.0, -0.1));
          else
            mm[c] = max(mm[c], val.clamp(0.1, 1.0));
          if (i % passo == 0) {
            int ii = i ~/ passo;
            if (ii < nVal) values[c][ii] = mm[c];
            mm[c] = 0;
          }
        }
      }
    }
    print("parseOsc $nChannels $nPoints");
    return values;
  }

  @override
  void paint(Canvas canvas, Size size) {
    //print("Paint");
    if (height == 0) return;
    canvas.drawRect(Rect.fromLTRB(0.0, 0.0, width, height), mRectPaint);
    if (values == null) {
      canvas.drawRect(
          Rect.fromLTRB(0.0, 0.0, percent * width, height), mBluePaint);
      return;
    }
    int lastx = -1;
    double wx = width / values![0].length;
    double hm1 = .45 * height, hm2 = .5 * height;
    double hs1 = .225 * height, hs2 = .25 * height, hs3 = .75 * height;
    for (int i = 0; i < values![0].length; i++) {
      int x = (i * wx).round();
      if (values![0][i] < mMinL) mMinL = values![0][i];
      if (values![1][i] > mMaxL) mMaxL = values![1][i];
      if(values!.length == 4) {
        if (values![2][i] < mMinR) mMinR = values![0][i];
        if (values![3][i] > mMaxR) mMaxR = values![1][i];
      }
      if (x % 4 == 0 && x != lastx) {
        lastx = x;
        //print("$x ${values[0][i]},${values[1][i]} ");
        bool blue = percent == 0 || x / width <= percent;
        if (values!.length == 4) //stereo
        {
          canvas.drawLine(
              Offset(x.toDouble(), hs2 + mMinL * hs1),
              Offset(x.toDouble(), hs2 + mMaxL * hs1),
              blue ? mBluePaint : mGrayPaint);
          canvas.drawLine(
              Offset(x.toDouble(), hs3 + mMinR * hs1),
              Offset(x.toDouble(), hs3 + mMaxR * hs1),
              blue ? mBluePaint : mGrayPaint);
        } else //mono
          canvas.drawLine(
              Offset(x.toDouble(), hm2 + mMinL * hm1),
              Offset(x.toDouble(), hm2 + mMaxL * hm1),
              blue ? mBluePaint : mGrayPaint);
        mMinL = 0;
        mMaxL = 0;
        mMinR = 0;
        mMaxR = 0;
      }
    }
  }

  @override
  bool shouldRepaint(Oscillo oldDelegate) {
    return true;
  }
}
