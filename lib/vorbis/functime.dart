import 'buffer.dart';
import 'block.dart';
import 'info.dart';
import 'dspstate.dart';

abstract class FuncTime{
  static List<FuncTime> time_P = [new Time0()];

  void pack(Object i, Buffer opb);

  Object unpack(Info vi, Buffer opb);

  Object look(DspState vd, InfoMode vm, Object i);

  void free_info(Object i);

  void free_look(Object i);

  int inverse(Block vb, Object i, List<double> inn, List<double> out);
}

class Time0 extends FuncTime{
  void pack(Object i, Buffer opb){
  }

  Object unpack(Info vi, Buffer opb){
    return "";
  }

  Object look(DspState vd, InfoMode mi, Object i){
    return "";
  }

  void free_info(Object i){
  }

  void free_look(Object i){
  }

  int inverse(Block vb, Object i, List<double> inn,  List<double> out){
    return 0;
  }
}