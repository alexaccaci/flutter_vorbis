import 'dart:typed_data';
import 'dart:convert';
import 'ogg.dart';
import 'codebook.dart';
import 'buffer.dart';
import 'util.dart';
import 'functime.dart';
import 'funcmapping.dart';
import 'funcfloor.dart';
import 'funcresidue.dart';
import 'comment.dart';

class Info{
  static final int OV_EBADPACKET=-136;
  static final int OV_ENOTAUDIO=-135;

  static Uint8List _vorbis=ascii.encode("vorbis");
  static final int VI_TIMEB=1;
  //   static final int VI_FLOORB=1;
  static final int VI_FLOORB=2;
  //   static final int VI_RESB=1;
  static final int VI_RESB=3;
  static final int VI_MAPB=1;
  static final int VI_WINDOWB=1;

  int version = 0;
  int channels = 0;
  int rate  = 0;

  int bitrate_upper = 0;
  int bitrate_nominal = 0;
  int bitrate_lower = 0;

  List<int> blocksizes = List.filled(2, 0);

  int modes = 0;
  int maps = 0;
  int times = 0;
  int floors = 0;
  int residues = 0;
  int books = 0;

  List<InfoMode?> mode_param = [];

  List<int> map_type = [];
  List<Object?> map_param = [];

  List<int> time_type = [];
  List<Object?> time_param = [];

  List<int> floor_type = [];
  List<Object?> floor_param = [];

  List<int> residue_type = [];
  List<Object?> residue_param = [];

  List<StaticCodeBook?> book_param = [];

  int envelopesa = 0;
  double preecho_thresh = 0;
  double preecho_clamp = 0;

  void init(){
    rate=0;
  }

  void clear(){
    for(int i=0; i<modes; i++){
      mode_param[i]=null;
    }
    mode_param.clear();

    for(int i=0; i<maps; i++){ // unpack does the range checking
      FuncMapping.mapping_P[map_type[i]].free_info(map_param[i]!);
    }
    map_param.clear();

    for(int i=0; i<times; i++){ // unpack does the range checking
      FuncTime.time_P[time_type[i]].free_info(time_param[i]!);
    }
    time_param.clear();

    for(int i=0; i<floors; i++){ // unpack does the range checking
      FuncFloor.floor_P[floor_type[i]].free_info(floor_param[i]!);
    }
    floor_param.clear();

    for(int i=0; i<residues; i++){ // unpack does the range checking
      FuncResidue.residue_P[residue_type[i]].free_info(residue_param[i]!);
    }
    residue_param.clear();

    for(int i=0; i<books; i++){
      // just in case the decoder pre-cleared to save space
      if(book_param[i]!=null){
        book_param[i]!.clear();
        book_param[i]=null;
      }
    }
    //if(vi->book_param)free(vi->book_param);
    book_param.clear();

  }

  // Header packing/unpacking
  int unpack_info(Buffer opb){
    version=opb.read0(32);
    if(version!=0)
      return (-1);

    channels=opb.read0(8);
    rate=opb.read0(32);

    bitrate_upper=opb.read0(32);
    bitrate_nominal=opb.read0(32);
    bitrate_lower=opb.read0(32);

    blocksizes[0]=1<<opb.read0(4);
    blocksizes[1]=1<<opb.read0(4);

    if((rate<1)||(channels<1)||(blocksizes[0]<8)||(blocksizes[1]<blocksizes[0])
        ||(opb.read0(1)!=1)){
      clear();
      return (-1);
    }
    return (0);
  }

  int unpack_books(Buffer opb){

    books=opb.read0(8)+1;

    if(book_param==null||book_param.length!=books)
      book_param=List.filled(books, null);
    for(int i=0; i<books; i++){
      book_param[i]=new StaticCodeBook();
      if(book_param[i]?.unpack(opb)!=0){
        clear();
        return (-1);
      }
    }

    // time backend settings
    times=opb.read0(6)+1;
    if(time_type==null||time_type.length!=times)
      time_type=List.filled(times, 0);
    if(time_param==null||time_param.length!=times)
      time_param=List.filled(times, null);
    for(int i=0; i<times; i++){
      time_type[i]=opb.read0(16);
      if(time_type[i]<0||time_type[i]>=VI_TIMEB){
        clear();
        return (-1);
      }
      time_param[i]=FuncTime.time_P[time_type[i]].unpack(this, opb);
      if(time_param[i]==null){
        clear();
        return (-1);
      }
    }

    // floor backend settings
    floors=opb.read0(6)+1;
    if(floor_type==null||floor_type.length!=floors)
      floor_type=List.filled(floors, 0);
    if(floor_param==null||floor_param.length!=floors)
      floor_param=List.filled(floors, null);

    for(int i=0; i<floors; i++){
      floor_type[i]=opb.read0(16);
      if(floor_type[i]<0||floor_type[i]>=VI_FLOORB){
        clear();
        return (-1);
      }

      floor_param[i]=FuncFloor.floor_P[floor_type[i]].unpack(this, opb);
      if(floor_param[i]==null){
        clear();
        return (-1);
      }
    }

    // residue backend settings
    residues=opb.read0(6)+1;

    if(residue_type==null||residue_type.length!=residues)
      residue_type=List.filled(residues, 0);

    if(residue_param==null||residue_param.length!=residues)
      residue_param=List.filled(residues, null);

    for(int i=0; i<residues; i++){
      residue_type[i]=opb.read0(16);
      if(residue_type[i]<0||residue_type[i]>=VI_RESB){
        clear();
        return (-1);
      }
      residue_param[i]=FuncResidue.residue_P[residue_type[i]].unpack(this, opb);
      if(residue_param[i]==null){
        clear();
        return (-1);
      }
    }

    // map backend settings
    maps=opb.read0(6)+1;
    if(map_type==null||map_type.length!=maps)
      map_type=List.filled(maps, 0);
    if(map_param==null||map_param.length!=maps)
      map_param=List.filled(maps, null);
    for(int i=0; i<maps; i++){
      map_type[i]=opb.read0(16);
      if(map_type[i]<0||map_type[i]>=VI_MAPB){
        clear();
        return (-1);
      }
      map_param[i]=FuncMapping.mapping_P[map_type[i]].unpack(this, opb);
      if(map_param[i]==null){
        clear();
        return (-1);
      }
    }

    // mode settings
    modes=opb.read0(6)+1;
    if(mode_param==null||mode_param.length!=modes)
      mode_param=List.filled(modes, null);
    for(int i=0; i<modes; i++){
      mode_param[i]=new InfoMode();
      mode_param[i]!.blockflag=opb.read0(1);
      mode_param[i]!.windowtype=opb.read0(16);
      mode_param[i]!.transformtype=opb.read0(16);
      mode_param[i]!.mapping=opb.read0(8);

      if((mode_param[i]!.windowtype>=VI_WINDOWB)
          ||(mode_param[i]!.transformtype>=VI_WINDOWB)
          ||(mode_param[i]!.mapping>=maps)){
        clear();
        return (-1);
      }
    }

    if(opb.read0(1)!=1){
      clear();
      return (-1);
    }

    return (0);
  }

  int synthesis_headerin(Comment vc, Packet op){
    Buffer opb = Buffer();

    if(op!=null){
      opb.readinit0(op.packet_base!, op.packet, op.bytes);

      var buffer = Uint8List(6);
      int packtype=opb.read0(8);
      opb.read(buffer, 6);
      if(buffer[0]!='v'.codeUnits.first||buffer[1]!='o'.codeUnits.first||buffer[2]!='r'.codeUnits.first||buffer[3]!='b'.codeUnits.first
          ||buffer[4]!='i'.codeUnits.first||buffer[5]!='s'.codeUnits.first){
        // not a vorbis header
        return (-1);
      }
      switch(packtype){
        case 0x01: // least significant *bit* is read first
          if(op.b_o_s==0){
            // Not the initial packet
            return (-1);
          }
          if(rate!=0){
            // previously initialized info header
            return (-1);
          }
          return (unpack_info(opb));
        case 0x03: // least significant *bit* is read first
          if(rate==0){
            // um... we didn't get the initial header
            return (-1);
          }
          return (vc.unpack(opb));
        case 0x05: // least significant *bit* is read first
          if(rate==0||vc.vendor==null){
            // um... we didn;t get the initial header or comments yet
            return (-1);
          }
          return (unpack_books(opb));
        default:
        // Not a valid vorbis header type
        //return(-1);
          break;
      }
    }
    return (-1);
  }

  // pack side
  int pack_info(Buffer opb){
    // preamble
    opb.write0(0x01, 8);
    opb.write(_vorbis);

    // basic information about the stream
    opb.write0(0x00, 32);
    opb.write0(channels, 8);
    opb.write0(rate, 32);

    opb.write0(bitrate_upper, 32);
    opb.write0(bitrate_nominal, 32);
    opb.write0(bitrate_lower, 32);

    opb.write0(Util.ilog2(blocksizes[0]), 4);
    opb.write0(Util.ilog2(blocksizes[1]), 4);
    opb.write0(1, 1);
    return (0);
  }

  int pack_books(Buffer opb){
    opb.write0(0x05, 8);
    opb.write(_vorbis);

    // books
    opb.write0(books-1, 8);
    for(int i=0; i<books; i++){
      if(book_param[i]?.pack(opb)!=0){
        //goto err_out;
        return (-1);
      }
    }

    // times
    opb.write0(times-1, 6);
    for(int i=0; i<times; i++){
      opb.write0(time_type[i], 16);
      FuncTime.time_P[time_type[i]].pack(this.time_param[i]!, opb);
    }

    // floors
    opb.write0(floors-1, 6);
    for(int i=0; i<floors; i++){
      opb.write0(floor_type[i], 16);
      FuncFloor.floor_P[floor_type[i]].pack(floor_param[i]!, opb);
    }

    // residues
    opb.write0(residues-1, 6);
    for(int i=0; i<residues; i++){
      opb.write0(residue_type[i], 16);
      FuncResidue.residue_P[residue_type[i]].pack(residue_param[i]!, opb);
    }

    // maps
    opb.write0(maps-1, 6);
    for(int i=0; i<maps; i++){
      opb.write0(map_type[i], 16);
      FuncMapping.mapping_P[map_type[i]].pack(this, map_param[i]!, opb);
    }

    // modes
    opb.write0(modes-1, 6);
    for(int i=0; i<modes; i++){
      opb.write0(mode_param[i]!.blockflag, 1);
      opb.write0(mode_param[i]!.windowtype, 16);
      opb.write0(mode_param[i]!.transformtype, 16);
      opb.write0(mode_param[i]!.mapping, 8);
    }
    opb.write0(1, 1);
    return (0);
  }

  int blocksize(Packet op){
    //codec_setup_info
    Buffer opb=new Buffer();

    int mode;

    opb.readinit0(op.packet_base!, op.packet, op.bytes);

    /* Check the packet type */
    if(opb.read0(1)!=0){
      /* This is not an audio packet */
      return (OV_ENOTAUDIO);
    }

    int modebits=0;
    int v=modes;
    while(v>1){
        modebits++;
        v>>=1;
    }
    mode=opb.read0(modebits);

    if(mode==-1)
    return (OV_EBADPACKET);
    return (blocksizes[mode_param[mode]!.blockflag]);
  }

  String toString(){
    return "version:$version, channels:$channels, rate:$rate, bitrate:$bitrate_upper,$bitrate_nominal$bitrate_lower";
  }
}

class InfoMode{
  int blockflag = 0;
  int windowtype = 0;
  int transformtype = 0;
  int mapping = 0;
}
