import 'buffer.dart';
import 'dspstate.dart';
import 'ogg.dart';
import 'info.dart';
import 'funcmapping.dart';

class Block{
  List<List<double>> pcm = [];
  Buffer opb = Buffer();

  int lW = 0;
  int W = 0;
  int nW = 0;
  int pcmend = 0;
  int mode = 0;

  int eofflag = 0;
  int granulepos = 0;
  int sequence = 0;
  late DspState vd;

  int glue_bits = 0;
  int time_bits = 0;
  int floor_bits = 0;
  int res_bits = 0;

  Block(DspState vd){
    this.vd=vd;
    if(vd.analysisp!=0){
      opb.writeinit();
    }
  }

  void init(DspState vd){
    this.vd=vd;
  }

  int clear(){
    if(vd!=null){
      if(vd.analysisp!=0){
        opb.writeclear();
      }
    }
    return (0);
  }

  int synthesis(Packet op){
    Info vi=vd.vi;

    opb.readinit0(op.packet_base!, op.packet, op.bytes);

    if(opb.read0(1)!=0){
      // Not an audio packet
      return (-1);
    }

    int _mode=opb.read0(vd.modebits);
    if(_mode==-1)
      return (-1);

    mode=_mode;
    W=vi.mode_param[mode]!.blockflag;
    if(W!=0){
      lW=opb.read0(1);
      nW=opb.read0(1);
      if(nW==-1)
        return (-1);
    }
    else{
      lW=0;
      nW=0;
    }

    granulepos=op.granulepos;
    sequence=op.packetno-3;
    eofflag=op.e_o_s;

    pcmend=vi.blocksizes[W];
    pcm=List.generate(vi.channels,(_) => List.generate(pcmend,(_) => 0));

    int type=vi.map_type[vi.mode_param[mode]!.mapping];
    return (FuncMapping.mapping_P[type].inverse(this, vd.mode[mode]));
  }
}
