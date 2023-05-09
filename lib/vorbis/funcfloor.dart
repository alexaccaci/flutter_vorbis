import 'dart:math';
import 'buffer.dart';
import 'info.dart';
import 'block.dart';
import 'dspstate.dart';
import 'util.dart';
import 'codebook.dart';
import 'lsp.dart';
import 'lpc.dart';

abstract class FuncFloor{

  static List<FuncFloor> floor_P= [new Floor0(), new Floor1()];

  void pack(Object i, Buffer opb);

  Object? unpack(Info vi, Buffer opb);

  Object look(DspState vd, InfoMode mi, Object i);

  void free_info(Object i);

  void free_look(Object i);

  void free_state(Object vs);

  int forward(Block vb, Object i, List<double> inn, List<double> out, Object vs);

  Object? inverse1(Block vb, Object i, Object? memo);

  int inverse2(Block vb, Object i, Object? memo, List<double> out);
}

class Floor0 extends FuncFloor {
  void pack(Object obj, Buffer opb) {
    InfoFloor0 info = obj as InfoFloor0;
    opb.write0(info.order, 8);
    opb.write0(info.rate, 16);
    opb.write0(info.barkmap, 16);
    opb.write0(info.ampbits, 6);
    opb.write0(info.ampdB, 8);
    opb.write0(info.numbooks - 1, 4);
    for (int j = 0; j < info.numbooks; j++) opb.write0(info.books[j], 8);
  }

  Object? unpack(Info vi, Buffer opb) {
    InfoFloor0 info = new InfoFloor0();
    info.order = opb.read0(8);
    info.rate = opb.read0(16);
    info.barkmap = opb.read0(16);
    info.ampbits = opb.read0(6);
    info.ampdB = opb.read0(8);
    info.numbooks = opb.read0(4) + 1;

    if ((info.order < 1) ||
        (info.rate < 1) ||
        (info.barkmap < 1) ||
        (info.numbooks < 1)) {
      return (null);
    }

    for (int j = 0; j < info.numbooks; j++) {
      info.books[j] = opb.read0(8);
      if (info.books[j] < 0 || info.books[j] >= vi.books) {
        return (null);
      }
    }
    return (info);
  }

  Object look(DspState vd, InfoMode mi, Object i) {
    double scale;
    Info vi = vd.vi;
    InfoFloor0 info = i as InfoFloor0;
    LookFloor0 look = new LookFloor0();
    look.m = info.order;
    look.n = vi.blocksizes[mi.blockflag] ~/ 2;
    look.ln = info.barkmap;
    look.vi = info;
    look.lpclook.init(look.ln, look.m);

    // we choose a scaling constant so that:
    scale = look.ln / toBARK((info.rate / 2.0));

    look.linearmap = List.filled(look.n, 0);
    for (int j = 0; j < look.n; j++) {
      int val = (toBARK(((info.rate / 2.0) / look.n * j)) * scale)
          .floor(); // bark numbers represent band edges
      if (val >= look.ln) val = look.ln; // guard against the approximation
      look.linearmap[j] = val;
    }
    return look;
  }

  static double toBARK(double f) {
    return (13.1 * atan(.00074 * (f)) +
        2.24 * atan((f) * (f) * 1.85e-8) +
        1e-4 * (f));
  }

  Object state(Object i) {
    EchstateFloor0 state = new EchstateFloor0();
    InfoFloor0 info = i as InfoFloor0;

    // a safe size if usually too big (dim==1)
    state.codewords = List.filled(info.order, 0);
    state.curve = List.filled(info.barkmap, 0);
    state.frameno = -1;
    return (state);
  }

  void free_info(Object i) {}

  void free_look(Object i) {}

  void free_state(Object vs) {}

  int forward(
      Block vb, Object i, List<double> inn, List<double> out, Object vs) {
    return 0;
  }

  List<double>? lsp;

  int inverse(Block vb, Object i, List<double> out) {
    //System.err.println("Floor0.inverse "+i.getClass()+"]");
    LookFloor0 look = i as LookFloor0;
    InfoFloor0 info = look.vi!;
    int ampraw = vb.opb.read0(info.ampbits);
    if (ampraw > 0) {
      // also handles the -1 out of data case
      int maxval = (1 << info.ampbits) - 1;
      double amp = ampraw / maxval * info.ampdB;
      int booknum = vb.opb.read0(Util.ilog(info.numbooks));

      if (booknum != -1 && booknum < info.numbooks) {
        //synchronized(this){
        if (lsp == null || lsp!.length < look.m) {
          lsp = List.filled(look.m, 0);
        } else {
          for (int j = 0; j < look.m; j++) lsp![j] = 0.0;
        }

        CodeBook b = vb.vd.fullbooks[info.books[booknum]];
        double last = 0.0;

        for (int j = 0; j < look.m; j++) out[j] = 0.0;

        for (int j = 0; j < look.m; j += b.dim) {
          if (b.decodevs(lsp!, j, vb.opb, 1, -1) == -1) {
            for (int k = 0; k < look.n; k++) out[k] = 0.0;
            return (0);
          }
        }
        for (int j = 0; j < look.m;) {
          for (int k = 0; k < b.dim; k++, j++) lsp![j] += last;
          last = lsp![j - 1];
        }
        // take the coefficients back to a spectral envelope curve
        Lsp.lsp_to_curve(out, look.linearmap, look.n, look.ln, lsp!, look.m, amp,
            info.ampdB.toDouble());

        return (1);
        //}//sync
      }
    }
    return (0);
  }

  Object? inverse1(Block vb, Object i, Object? memo) {
    LookFloor0 look = i as LookFloor0;
    InfoFloor0 info = look.vi!;
    List<double>? lsp;
    if (memo is List<double>) {
      lsp = memo;
    }

    int ampraw = vb.opb.read0(info.ampbits);
    if (ampraw > 0) {
      // also handles the -1 out of data case
      int maxval = (1 << info.ampbits) - 1;
      double amp = ampraw / maxval * info.ampdB;
      int booknum = vb.opb.read0(Util.ilog(info.numbooks));

      if (booknum != -1 && booknum < info.numbooks) {
        CodeBook b = vb.vd.fullbooks[info.books[booknum]];
        double last = 0.0;

        if (lsp == null || lsp.length < look.m + 1) {
          lsp = List.filled(look.m + 1, 0);
        } else {
          for (int j = 0; j < lsp.length; j++) lsp[j] = 0.0;
        }

        for (int j = 0; j < look.m; j += b.dim) {
          if (b.decodev_set(lsp, j, vb.opb, b.dim) == -1) {
            return (null);
          }
        }

        for (int j = 0; j < look.m;) {
          for (int k = 0; k < b.dim; k++, j++) lsp[j] += last;
          last = lsp[j - 1];
        }
        lsp[look.m] = amp;
        return (lsp);
      }
    }
    return (null);
  }

  int inverse2(Block vb, Object i, Object? memo, List<double> out) {
    LookFloor0 look = i as LookFloor0;
    InfoFloor0 info = look.vi!;

    if (memo != null) {
      List<double> lsp = memo as List<double>;
      double amp = lsp[look.m];

      Lsp.lsp_to_curve(out, look.linearmap, look.n, look.ln, lsp, look.m, amp,
          info.ampdB.toDouble());
      return (1);
    }
    for (int j = 0; j < look.n; j++) {
      out[j] = 0.0;
    }
    return (0);
  }

  static double fromdB(double x) {
    return exp((x) * .11512925);
  }

  static void lsp_to_lpc(List<double> lsp, List<double> lpc, int m) {
    int i, j, m2 = m ~/ 2;
    List<double> O = List.filled(m2, 0);
    List<double> E = List.filled(m2, 0);
    double A;
    List<double> Ae = List.filled(m2 + 1, 0);
    List<double> Ao = List.filled(m2 + 1, 0);
    double B;
    List<double> Be = List.filled(m2, 0);
    List<double> Bo = List.filled(m2, 0);
    double temp;

    // even/odd roots setup
    for (i = 0; i < m2; i++) {
      O[i] = (-2.0 * cos(lsp[i * 2]));
      E[i] = (-2.0 * cos(lsp[i * 2 + 1]));
    }

    // set up impulse response
    for (j = 0; j < m2; j++) {
      Ae[j] = 0.0;
      Ao[j] = 1.0;
      Be[j] = 0.0;
      Bo[j] = 1.0;
    }
    Ao[j] = 1.0;
    Ae[j] = 1.0;

    // run impulse response
    for (i = 1; i < m + 1; i++) {
      A = B = 0.0;
      for (j = 0; j < m2; j++) {
        temp = O[j] * Ao[j] + Ae[j];
        Ae[j] = Ao[j];
        Ao[j] = A;
        A += temp;

        temp = E[j] * Bo[j] + Be[j];
        Be[j] = Bo[j];
        Bo[j] = B;
        B += temp;
      }
      lpc[i - 1] = (A + Ao[j] + B - Ae[j]) / 2;
      Ao[j] = A;
      Ae[j] = B;
    }
  }

  static void lpc_to_curve(List<double> curve, List<double> lpc, double amp,
      LookFloor0 l, String name, int frameno) {
    // l->m+1 must be less than l->ln, but guard in case we get a bad stream
    List<double> lcurve = List.filled(max(l.ln * 2, l.m * 2 + 2), 0);

    if (amp == 0) {
      for (int j = 0; j < l.n; j++) curve[j] = 0.0;
      return;
    }
    l.lpclook.lpc_to_curve(lcurve, lpc, amp);

    for (int i = 0; i < l.n; i++) curve[i] = lcurve[l.linearmap[i]];
  }
}

class InfoFloor0 {
  int order = 0;
  int rate = 0;
  int barkmap = 0;

  int ampbits = 0;
  int ampdB = 0;

  int numbooks = 0; // <= 16
  List<int> books = new List.generate(16,(_) => 0);
}

class LookFloor0 {
  int n = 0;
  int ln = 0;
  int m = 0;
  List<int> linearmap = [];

  InfoFloor0? vi;
  Lpc lpclook = new Lpc();
}

class EchstateFloor0 {
  List<int> codewords = [];
  List<double> curve = [];
  int frameno = 0;
  int codes = 0;
}


class Floor1 extends FuncFloor{
  static final int floor1_rangedb=140;
  static final int VIF_POSIT=63;

  void pack(Object obj, Buffer opb){
    InfoFloor1 info = obj as InfoFloor1;

    int count=0;
    int rangebits;
    int maxposit=info.postlist[1];
    int maxclass=-1;

    /* save out partitions */
    opb.write0(info.partitions, 5); /* only 0 to 31 legal */
    for(int j=0; j<info.partitions; j++){
      opb.write0(info.partitionclass[j], 4); /* only 0 to 15 legal */
      if(maxclass<info.partitionclass[j])
        maxclass=info.partitionclass[j];
    }

    /* save out partition classes */
    for(int j=0; j<maxclass+1; j++){
      opb.write0(info.class_dim[j]-1, 3); /* 1 to 8 */
      opb.write0(info.class_subs[j], 2); /* 0 to 3 */
      if(info.class_subs[j]!=0){
        opb.write0(info.class_book[j], 8);
      }
      for(int k=0; k<(1<<info.class_subs[j]); k++){
        opb.write0(info.class_subbook[j][k]+1, 8);
      }
    }

    /* save out the post list */
    opb.write0(info.mult-1, 2); /* only 1,2,3,4 legal now */
    opb.write0(Util.ilog2(maxposit), 4);
    rangebits=Util.ilog2(maxposit);

    for(int j=0, k=0; j<info.partitions; j++){
      count+=info.class_dim[info.partitionclass[j]];
      for(; k<count; k++){
        opb.write0(info.postlist[k+2], rangebits);
      }
    }
  }

  Object? unpack(Info vi, Buffer opb){
    int count=0, maxclass=-1, rangebits;
    InfoFloor1 info=new InfoFloor1();

    /* read partitions */
    info.partitions=opb.read0(5); /* only 0 to 31 legal */
    for(int j=0; j<info.partitions; j++){
      info.partitionclass[j]=opb.read0(4); /* only 0 to 15 legal */
      if(maxclass<info.partitionclass[j])
        maxclass=info.partitionclass[j];
    }

    /* read partition classes */
    for(int j=0; j<maxclass+1; j++){
      info.class_dim[j]=opb.read0(3)+1; /* 1 to 8 */
      info.class_subs[j]=opb.read0(2); /* 0,1,2,3 bits */
      if(info.class_subs[j]<0){
        info.free();
        return (null);
      }
      if(info.class_subs[j]!=0){
        info.class_book[j]=opb.read0(8);
      }
      if(info.class_book[j]<0||info.class_book[j]>=vi.books){
        info.free();
        return (null);
      }
      for(int k=0; k<(1<<info.class_subs[j]); k++){
        info.class_subbook[j][k]=opb.read0(8)-1;
        if(info.class_subbook[j][k]<-1||info.class_subbook[j][k]>=vi.books){
          info.free();
          return (null);
        }
      }
    }

    /* read the post list */
    info.mult=opb.read0(2)+1; /* only 1,2,3,4 legal now */
    rangebits=opb.read0(4);

    for(int j=0, k=0; j<info.partitions; j++){
      count+=info.class_dim[info.partitionclass[j]];
      for(; k<count; k++){
        int t=info.postlist[k+2]=opb.read0(rangebits);
        if(t<0||t>=(1<<rangebits)){
          info.free();
          return (null);
        }
      }
    }
    info.postlist[0]=0;
    info.postlist[1]=1<<rangebits;

    return (info);
  }

  Object look(DspState vd, InfoMode mi, Object i){
    int _n=0;

    List<int> sortpointer=List.filled(VIF_POSIT+2,0);

    //    Info vi=vd.vi;

    InfoFloor1 info = i as InfoFloor1;
    LookFloor1 look=new LookFloor1();
    look.vi=info;
    look.n=info.postlist[1];

    for(int j=0; j<info.partitions; j++){
      _n+=info.class_dim[info.partitionclass[j]];
    }
    _n+=2;
    look.posts=_n;

    for(int j=0; j<_n; j++){
      sortpointer[j]=j;
    }

    int foo;
    for(int j=0; j<_n-1; j++){
      for(int k=j; k<_n; k++){
        if(info.postlist[sortpointer[j]]>info.postlist[sortpointer[k]]){
          foo=sortpointer[k];
          sortpointer[k]=sortpointer[j];
          sortpointer[j]=foo;
        }
      }
    }

    for(int j=0; j<_n; j++){
      look.forward_index[j]=sortpointer[j];
    }
    for(int j=0; j<_n; j++){
      look.reverse_index[look.forward_index[j]]=j;
    }
    for(int j=0; j<_n; j++){
      look.sorted_index[j]=info.postlist[look.forward_index[j]];
    }

    /* quantize values to multiplier spec */
    switch(info.mult){
      case 1: /* 1024 -> 256 */
        look.quant_q=256;
        break;
      case 2: /* 1024 -> 128 */
        look.quant_q=128;
        break;
      case 3: /* 1024 -> 86 */
        look.quant_q=86;
        break;
      case 4: /* 1024 -> 64 */
        look.quant_q=64;
        break;
      default:
        look.quant_q=-1;
    }

    for(int j=0; j<_n-2; j++){
      int lo=0;
      int hi=1;
      int lx=0;
      int hx=look.n;
      int currentx=info.postlist[j+2];
      for(int k=0; k<j+2; k++){
        int x=info.postlist[k];
        if(x>lx&&x<currentx){
          lo=k;
          lx=x;
        }
        if(x<hx&&x>currentx){
          hi=k;
          hx=x;
        }
      }
      look.loneighbor[j]=lo;
      look.hineighbor[j]=hi;
    }

    return look;
  }

  void free_info(Object i){
  }

  void free_look(Object i){
  }

  void free_state(Object vs){
  }

  int forward(Block vb, Object i, List<double> inn, List<double> out, Object vs){
    return 0;
  }

  Object? inverse1(Block vb, Object ii, Object? memo){
    LookFloor1 look = ii as LookFloor1;
    InfoFloor1 info=look.vi!;
    List<CodeBook> books=vb.vd.fullbooks;

    /* unpack wrapped/predicted values from stream */
    if(vb.opb.read0(1)==1){
      List<int>? fit_value;
      if(memo is List<int>){
        fit_value=memo;
      }
      if(fit_value==null||fit_value.length<look.posts){
        fit_value=List.filled(look.posts,0);
      }
      else{
        for(int i=0; i<fit_value.length; i++)
          fit_value[i]=0;
      }

      fit_value[0]=vb.opb.read0(Util.ilog(look.quant_q-1));
      fit_value[1]=vb.opb.read0(Util.ilog(look.quant_q-1));

      /* partition by partition */
      for(int i=0, j=2; i<info.partitions; i++){
        int clss=info.partitionclass[i];
        int cdim=info.class_dim[clss];
        int csubbits=info.class_subs[clss];
        int csub=1<<csubbits;
        int cval=0;

        /* decode the partition's first stage cascade value */
        if(csubbits!=0){
          cval=books[info.class_book[clss]].decode(vb.opb);

          if(cval==-1){
            return (null);
          }
        }

        for(int k=0; k<cdim; k++){
          int book=info.class_subbook[clss][cval&(csub-1)];
          cval>>=csubbits;
          if(book>=0){
            if((fit_value[j+k]=books[book].decode(vb.opb))==-1){
              return (null);
            }
          }
          else{
            fit_value[j+k]=0;
          }
        }
        j+=cdim;
      }

      /* unwrap positive values and reconsitute via linear interpolation */
      for(int i=2; i<look.posts; i++){
        int predicted=render_point(info.postlist[look.loneighbor[i-2]],
            info.postlist[look.hineighbor[i-2]],
            fit_value[look.loneighbor[i-2]], fit_value[look.hineighbor[i-2]],
            info.postlist[i]);
        int hiroom=look.quant_q-predicted;
        int loroom=predicted;
        int room=(hiroom<loroom ? hiroom : loroom)<<1;
        int val=fit_value[i];

        if(val!=0){
          if(val>=room){
            if(hiroom>loroom){
              val=val-loroom;
            }
            else{
              val=-1-(val-hiroom);
            }
          }
          else{
            if((val&1)!=0){
              val=-((val+1)>>1);
            }
            else{
              val>>=1;
            }
          }

          fit_value[i]=val+predicted;
          fit_value[look.loneighbor[i-2]]&=0x7fff;
          fit_value[look.hineighbor[i-2]]&=0x7fff;
        }
        else{
          fit_value[i]=predicted|0x8000;
        }
      }
      return (fit_value);
    }

    return (null);
  }

  static int render_point(int x0, int x1, int y0, int y1, int x){
    y0&=0x7fff; /* mask off flag */
    y1&=0x7fff;

    {
      int dy=y1-y0;
      int adx=x1-x0;
      int ady=dy.abs();
      int err=ady*(x-x0);

      int off=err~/adx;
      if(dy<0)
        return (y0-off);
      return (y0+off);
    }
  }

  int inverse2(Block vb, Object i, Object? memo, List<double> out){
    LookFloor1 look = i as LookFloor1;
    InfoFloor1 info=look.vi!;
    int n=vb.vd.vi.blocksizes[vb.mode]~/2;

    if(memo!=null){
      /* render the lines */
      List<int> fit_value=memo as List<int>;
      int hx=0;
      int lx=0;
      int ly=fit_value[0]*info.mult;
      for(int j=1; j<look.posts; j++){
        int current=look.forward_index[j];
        int hy=fit_value[current]&0x7fff;
        if(hy==fit_value[current]){
          hy*=info.mult;
          hx=info.postlist[current];

          render_line(lx, hx, ly, hy, out);

          lx=hx;
          ly=hy;
        }
      }
      for(int j=hx; j<n; j++){
        out[j]*=out[j-1]; /* be certain */
      }
      return (1);
    }
    for(int j=0; j<n; j++){
      out[j]=0.0;
    }
    return (0);
  }

  static List<double> FLOOR_fromdB_LOOKUP= [1.0649863e-07, 1.1341951e-07,
  1.2079015e-07, 1.2863978e-07, 1.3699951e-07, 1.4590251e-07,
  1.5538408e-07, 1.6548181e-07, 1.7623575e-07, 1.8768855e-07,
  1.9988561e-07, 2.128753e-07, 2.2670913e-07, 2.4144197e-07,
  2.5713223e-07, 2.7384213e-07, 2.9163793e-07, 3.1059021e-07,
  3.3077411e-07, 3.5226968e-07, 3.7516214e-07, 3.9954229e-07,
  4.2550680e-07, 4.5315863e-07, 4.8260743e-07, 5.1396998e-07,
  5.4737065e-07, 5.8294187e-07, 6.2082472e-07, 6.6116941e-07,
  7.0413592e-07, 7.4989464e-07, 7.9862701e-07, 8.5052630e-07,
  9.0579828e-07, 9.6466216e-07, 1.0273513e-06, 1.0941144e-06,
  1.1652161e-06, 1.2409384e-06, 1.3215816e-06, 1.4074654e-06,
  1.4989305e-06, 1.5963394e-06, 1.7000785e-06, 1.8105592e-06,
  1.9282195e-06, 2.0535261e-06, 2.1869758e-06, 2.3290978e-06,
  2.4804557e-06, 2.6416497e-06, 2.8133190e-06, 2.9961443e-06,
  3.1908506e-06, 3.3982101e-06, 3.6190449e-06, 3.8542308e-06,
  4.1047004e-06, 4.3714470e-06, 4.6555282e-06, 4.9580707e-06,
  5.2802740e-06, 5.6234160e-06, 5.9888572e-06, 6.3780469e-06,
  6.7925283e-06, 7.2339451e-06, 7.7040476e-06, 8.2047000e-06,
  8.7378876e-06, 9.3057248e-06, 9.9104632e-06, 1.0554501e-05,
  1.1240392e-05, 1.1970856e-05, 1.2748789e-05, 1.3577278e-05,
  1.4459606e-05, 1.5399272e-05, 1.6400004e-05, 1.7465768e-05,
  1.8600792e-05, 1.9809576e-05, 2.1096914e-05, 2.2467911e-05,
  2.3928002e-05, 2.5482978e-05, 2.7139006e-05, 2.8902651e-05,
  3.0780908e-05, 3.2781225e-05, 3.4911534e-05, 3.7180282e-05,
  3.9596466e-05, 4.2169667e-05, 4.4910090e-05, 4.7828601e-05,
  5.0936773e-05, 5.4246931e-05, 5.7772202e-05, 6.1526565e-05,
  6.5524908e-05, 6.9783085e-05, 7.4317983e-05, 7.9147585e-05,
  8.4291040e-05, 8.9768747e-05, 9.5602426e-05, 0.00010181521,
  0.00010843174, 0.00011547824, 0.00012298267, 0.00013097477,
  0.00013948625, 0.00014855085, 0.00015820453, 0.00016848555,
  0.00017943469, 0.00019109536, 0.00020351382, 0.00021673929,
  0.00023082423, 0.00024582449, 0.00026179955, 0.00027881276,
  0.00029693158, 0.00031622787, 0.00033677814, 0.00035866388,
  0.00038197188, 0.00040679456, 0.00043323036, 0.00046138411,
  0.00049136745, 0.00052329927, 0.00055730621, 0.00059352311,
  0.00063209358, 0.00067317058, 0.00071691700, 0.00076350630,
  0.00081312324, 0.00086596457, 0.00092223983, 0.00098217216,
  0.0010459992, 0.0011139742, 0.0011863665, 0.0012634633,
  0.0013455702, 0.0014330129, 0.0015261382, 0.0016253153,
  0.0017309374, 0.0018434235, 0.0019632195, 0.0020908006,
  0.0022266726, 0.0023713743, 0.0025254795, 0.0026895994,
  0.0028643847, 0.0030505286, 0.0032487691, 0.0034598925,
  0.0036847358, 0.0039241906, 0.0041792066, 0.0044507950,
  0.0047400328, 0.0050480668, 0.0053761186, 0.0057254891,
  0.0060975636, 0.0064938176, 0.0069158225, 0.0073652516,
  0.0078438871, 0.0083536271, 0.0088964928, 0.009474637, 0.010090352,
  0.010746080, 0.011444421, 0.012188144, 0.012980198, 0.013823725,
  0.014722068, 0.015678791, 0.016697687, 0.017782797, 0.018938423,
  0.020169149, 0.021479854, 0.022875735, 0.024362330, 0.025945531,
  0.027631618, 0.029427276, 0.031339626, 0.033376252, 0.035545228,
  0.037855157, 0.040315199, 0.042935108, 0.045725273, 0.048696758,
  0.051861348, 0.055231591, 0.058820850, 0.062643361, 0.066714279,
  0.071049749, 0.075666962, 0.080584227, 0.085821044, 0.091398179,
  0.097337747, 0.10366330, 0.11039993, 0.11757434, 0.12521498,
  0.13335215, 0.14201813, 0.15124727, 0.16107617, 0.17154380,
  0.18269168, 0.19456402, 0.20720788, 0.22067342, 0.23501402,
  0.25028656, 0.26655159, 0.28387361, 0.30232132, 0.32196786,
  0.34289114, 0.36517414, 0.38890521, 0.41417847, 0.44109412,
  0.46975890, 0.50028648, 0.53279791, 0.56742212, 0.60429640,
  0.64356699, 0.68538959, 0.72993007, 0.77736504, 0.82788260,
  0.88168307, 0.9389798, 1.0];

  static void render_line(int x0, int x1, int y0, int y1, List<double> d){
    int dy=y1-y0;
    int adx=x1-x0;
    int ady=dy.abs();
    int base=dy~/adx;
    int sy=(dy<0 ? base-1 : base+1);
    int x=x0;
    int y=y0;
    int err=0;

    ady-=(base*adx).abs();

    d[x]*=FLOOR_fromdB_LOOKUP[y];
    while(++x<x1){
      err=err+ady;
      if(err>=adx){
        err-=adx;
        y+=sy;
      }
      else{
        y+=base;
      }
      d[x]*=FLOOR_fromdB_LOOKUP[y];
    }
  }
}

class InfoFloor1{
  static final int VIF_POSIT=63;
  static final int VIF_CLASS=16;
  static final int VIF_PARTS=31;

  int partitions = 0; /* 0 to 31 */
  List<int> partitionclass=new List.filled(VIF_PARTS, 0); /* 0 to 15 */

  List<int> class_dim=new List.filled(VIF_CLASS, 0); /* 1 to 8 */
  List<int> class_subs=new List.filled(VIF_CLASS, 0); /* 0,1,2,3 (bits: 1<<n poss) */
  List<int> class_book=new List.filled(VIF_CLASS, 0); /* subs ^ dim entries */
  List<List<int>>  class_subbook= List.generate(VIF_CLASS, (_) => []); /* [VIF_CLASS][subs] */

  int mult = 0; /* 1 2 3 or 4 */
  List<int> postlist=new List.filled(VIF_POSIT+2, 0); /* first two implicit */

  /* encode side analysis parameters */
  double maxover = 0;
  double maxunder = 0;
  double maxerr = 0;

  int twofitminsize = 0;
  int twofitminused = 0;
  int twofitweight = 0;
  double twofitatten = 0;
  int unusedminsize = 0;
  int unusedmin_n = 0;

  int n = 0;

  InfoFloor1(){
    for(int i=0; i<class_subbook.length; i++){
      class_subbook[i]=new List.generate(8,(_) => 0);
    }
  }

  void free(){
    partitionclass.clear();
    class_dim.clear();
    class_subs.clear();
    class_book.clear();
    class_subbook.clear();
    postlist.clear();
  }

  Object copy_info(){
    InfoFloor1 info=this;
    InfoFloor1 ret=new InfoFloor1();

    ret.partitions=info.partitions;
    //System.arraycopy(info.partitionclass, 0, ret.partitionclass, 0, VIF_PARTS);
    ret.partitionclass.setAll(0, info.partitionclass);
    //System.arraycopy(info.class_dim, 0, ret.class_dim, 0, VIF_CLASS);
    ret.class_dim.setAll(0, info.class_dim);
    //System.arraycopy(info.class_subs, 0, ret.class_subs, 0, VIF_CLASS);
    ret.class_subs.setAll(0, info.class_subs);
    //System.arraycopy(info.class_book, 0, ret.class_book, 0, VIF_CLASS);
    ret.class_book.setAll(0, info.class_book);

    for(int j=0; j<VIF_CLASS; j++){
      //System.arraycopy(info.class_subbook[j], 0, ret.class_subbook[j], 0, 8);
      ret.class_subbook[j].setAll(0, info.class_subbook[j]);
    }

    ret.mult=info.mult;
    //System.arraycopy(info.postlist, 0, ret.postlist, 0, VIF_POSIT+2);
    ret.postlist.setAll(0, info.postlist);

    ret.maxover=info.maxover;
    ret.maxunder=info.maxunder;
    ret.maxerr=info.maxerr;

    ret.twofitminsize=info.twofitminsize;
    ret.twofitminused=info.twofitminused;
    ret.twofitweight=info.twofitweight;
    ret.twofitatten=info.twofitatten;
    ret.unusedminsize=info.unusedminsize;
    ret.unusedmin_n=info.unusedmin_n;

    ret.n=info.n;

    return (ret);
  }

}

class LookFloor1{
  static final int VIF_POSIT=63;

  List<int> sorted_index = List.filled(VIF_POSIT+2,0);
  List<int> forward_index = List.filled(VIF_POSIT+2,0);
  List<int> reverse_index = List.filled(VIF_POSIT+2,0);
  List<int> hineighbor = List.filled(VIF_POSIT,0);
  List<int> loneighbor = List.filled(VIF_POSIT,0);
  int posts = 0;

  int n = 0;
  int quant_q = 0;
  InfoFloor1? vi;

  int phrasebits = 0;
  int postbits = 0;
  int frames = 0;

  void free(){
    sorted_index.clear();
    forward_index.clear();
    reverse_index.clear();
    hineighbor.clear();
    loneighbor.clear();
  }
}

class Lsfit_acc{
  int x0 = 0;
  int x1 = 0;

  int xa = 0;
  int ya = 0;
  int x2a = 0;
  int y2a = 0;
  int xya = 0;
  int n = 0;
  int an = 0;
  int un = 0;
  int edgey0 = 0;
  int edgey1 = 0;
}

class EchstateFloor1{
  late List<int> codewords;
  late List<double> curve;
  int frameno = 0;
  int codes = 0;
}

