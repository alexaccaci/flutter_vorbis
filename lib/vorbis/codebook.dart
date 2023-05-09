import 'dart:math';
import 'buffer.dart';
import 'util.dart';

class CodeBook {
  int dim = 0; // codebook dimensions (elements per vector)
  int entries = 0; // codebook entries
  StaticCodeBook c = new StaticCodeBook();

  List<double> valuelist = []; // list of dim*entries actual entry values
  DecodeAux? decode_tree;

  int errorv(List<double> a) {
    int besti = best(a, 1);
    for (int k = 0; k < dim; k++) {
      a[k] = valuelist[besti * dim + k];
    }
    return (besti);
  }

  List<int> t =
      List.filled(15, 0); // decodevs_add is synchronized for re-using t.

  //synchronized
  int decodevs_add(List<double> a, int offset, Buffer b, int n) {
    int step = n ~/ dim;
    int entry;
    int i, j, o;

    if (t.length < step) {
      t = List.filled(step,0);
    }

    for (i = 0; i < step; i++) {
      entry = decode(b);
      if (entry == -1) return (-1);
      t[i] = entry * dim;
    }

    for (o = i = 0; i < dim; i++, o += step) {
      for (j = 0; j < step; j++) {
        a[offset + o + j] += valuelist[t[j] + i];
      }
    }

    return (0);
  }

  int decodev_add(List<double> a, int offset, Buffer b, int n) {
    int i, j, entry;
    int t;

    if (dim > 8) {
      for (i = 0; i < n;) {
        entry = decode(b);
        if (entry == -1) return (-1);
        t = entry * dim;
        for (j = 0; j < dim;) {
          a[offset + (i++)] += valuelist[t + (j++)];
        }
      }
    } else {
      for (i = 0; i < n;) {
        entry = decode(b);
        if (entry == -1) return (-1);
        t = entry * dim;
        j = 0;
        for (int k = 0; k < dim; k++) a[offset + (i++)] += valuelist[t + (j++)];
      }
    }
    return (0);
  }

  int decodev_set(List<double> a, int offset, Buffer b, int n) {
    int i, j, entry;
    int t;

    for (i = 0; i < n;) {
      entry = decode(b);
      if (entry == -1) return (-1);
      t = entry * dim;
      for (j = 0; j < dim;) {
        a[offset + i++] = valuelist[t + (j++)];
      }
    }
    return (0);
  }

  int decodevv_add(List<List<double>> a, int offset, int ch, Buffer b, int n) {
    int i, j, entry;
    int chptr = 0;

    for (i = offset ~/ ch; i < (offset + n) / ch;) {
      entry = decode(b);
      if (entry == -1) return (-1);

      int t = entry * dim;
      for (j = 0; j < dim; j++) {
        a[chptr++][i] += valuelist[t + j];
        if (chptr == ch) {
          chptr = 0;
          i++;
        }
      }
    }
    return (0);
  }

  // returns the entry number or -1 on eof
  int decode(Buffer b) {
    int ptr = 0;
    DecodeAux t = decode_tree!;
    int lok = b.look(t.tabn);

    if (lok >= 0) {
      ptr = t.tab[lok];
      b.adv(t.tabl[lok]);
      if (ptr <= 0) {
        return -ptr;
      }
    }
    do {
      switch (b.read1()) {
        case 0:
          ptr = t.ptr0[ptr];
          break;
        case 1:
          ptr = t.ptr1[ptr];
          break;
        case -1:
        default:
          return (-1);
      }
    } while (ptr > 0);
    return (-ptr);
  }

  // returns the entry number or -1 on eof
  int decodevs(List<double> a, int index, Buffer b, int step, int addmul) {
    int entry = decode(b);
    if (entry == -1) return (-1);
    switch (addmul) {
      case -1:
        for (int i = 0, o = 0; i < dim; i++, o += step)
          a[index + o] = valuelist[entry * dim + i];
        break;
      case 0:
        for (int i = 0, o = 0; i < dim; i++, o += step)
          a[index + o] += valuelist[entry * dim + i];
        break;
      case 1:
        for (int i = 0, o = 0; i < dim; i++, o += step)
          a[index + o] *= valuelist[entry * dim + i];
        break;
      default:
        print("CodeBook.decodeves: addmul=$addmul");
    }
    return (entry);
  }

  int best(List<double> a, int step) {
    // brute force it!
    int besti = -1;
    double best = 0.0;
    int e = 0;
    for (int i = 0; i < entries; i++) {
      if (c.lengthlist[i] > 0) {
        double _this = dist(dim, valuelist, e, a, step);
        if (besti == -1 || _this < best) {
          best = _this;
          besti = i;
        }
      }
      e += dim;
    }
    return (besti);
  }

  // returns the entry number and *modifies a* to the remainder value
  int besterror(List<double> a, int step, int addmul) {
    int besti = best(a, step);
    switch (addmul) {
      case 0:
        for (int i = 0, o = 0; i < dim; i++, o += step)
          a[o] -= valuelist[besti * dim + i];
        break;
      case 1:
        for (int i = 0, o = 0; i < dim; i++, o += step) {
          double val = valuelist[besti * dim + i];
          if (val == 0) {
            a[o] = 0;
          } else {
            a[o] /= val;
          }
        }
        break;
    }
    return (besti);
  }

  void clear() {}

  static double dist(
      int el, List<double> ref, int index, List<double> b, int step) {
    double acc = 0.0;
    for (int i = 0; i < el; i++) {
      double val = (ref[index + i] - b[i * step]);
      acc += val * val;
    }
    return (acc);
  }

  int init_decode(StaticCodeBook s) {
    c = s;
    entries = s.entries;
    dim = s.dim;
    valuelist = s.unquantize();

    decode_tree = make_decode_tree();
    if (decode_tree == null) {
      clear();
      return (-1);
    }
    return (0);
  }

  static List<int>? make_words(List<int> l, int n) {
    List<int> marker = List.filled(33, 0);
    List<int> r = List.filled(n, 0);

    for (int i = 0; i < n; i++) {
      int length = l[i];
      if (length > 0) {
        int entry = marker[length];

        if (length < 32 && (entry >> length) != 0) {
          // error condition; the lengths must specify an overpopulated tree
          return (null);
        }
        r[i] = entry;

        {
          for (int j = length; j > 0; j--) {
            if ((marker[j] & 1) != 0) {
              // have to jump branches
              if (j == 1)
                marker[1]++;
              else
                marker[j] = marker[j - 1] << 1;
              break; // invariant says next upper marker would already
              // have been moved if it was on the same path
            }
            marker[j]++;
          }
        }

        for (int j = length + 1; j < 33; j++) {
          if ((marker[j] >> 1) == entry) {
            entry = marker[j];
            marker[j] = marker[j - 1] << 1;
          } else {
            break;
          }
        }
      }
    }

    for (int i = 0; i < n; i++) {
      int temp = 0;
      for (int j = 0; j < l[i]; j++) {
        temp <<= 1;
        temp |= (r[i] >> j) & 1;
      }
      r[i] = temp;
    }

    return (r);
  }

  // build the decode helper tree from the codewords
  DecodeAux? make_decode_tree() {
    int top = 0;
    DecodeAux t = new DecodeAux();
    List<int> ptr0 = t.ptr0 = new List.generate(entries * 2, (_) => 0);
    List<int> ptr1 = t.ptr1 = new List.generate(entries * 2, (_) => 0);
    List<int>? codelist = make_words(c.lengthlist, c.entries);

    if (codelist == null) return (null);
    t.aux = entries * 2;

    for (int i = 0; i < entries; i++) {
      if (c.lengthlist[i] > 0) {
        int ptr = 0;
        int j;
        for (j = 0; j < c.lengthlist[i] - 1; j++) {
          int bit = (codelist[i] >> j) & 1;
          if (bit == 0) {
            if (ptr0[ptr] == 0) {
              ptr0[ptr] = ++top;
            }
            ptr = ptr0[ptr];
          } else {
            if (ptr1[ptr] == 0) {
              ptr1[ptr] = ++top;
            }
            ptr = ptr1[ptr];
          }
        }

        if (((codelist[i] >> j) & 1) == 0) {
          ptr0[ptr] = -i;
        } else {
          ptr1[ptr] = -i;
        }
      }
    }

    t.tabn = Util.ilog(entries) - 4;

    if (t.tabn < 5) t.tabn = 5;
    int n = 1 << t.tabn;
    t.tab =  List.filled(n, 0);
    t.tabl = List.filled(n, 0);
    for (int i = 0; i < n; i++) {
      int p = 0;
      int j = 0;
      for (j = 0; j < t.tabn && (p > 0 || j == 0); j++) {
        if ((i & (1 << j)) != 0) {
          p = ptr1[p];
        } else {
          p = ptr0[p];
        }
      }
      t.tab[i] = p; // -code
      t.tabl[i] = j; // length
    }

    return (t);
  }
}

class DecodeAux {
  List<int> tab = [];
  List<int> tabl = [];
  int tabn = 0;

  List<int> ptr0 = [];
  List<int> ptr1 = [];
  int aux = 0; // number of tree entries
}

class StaticCodeBook{
  int dim = 0; // codebook dimensions (elements per vector)
  int entries = 0; // codebook entries
  List<int> lengthlist = []; // codeword lengths in bits

  // mapping
  int maptype = 0; // 0=none
  // 1=implicitly populated values from map column
  // 2=listed arbitrary values

  // The below does a linear, single monotonic sequence mapping.
  int q_min = 0; // packed 32 bit float; quant value 0 maps to minval
  int q_delta = 0; // packed 32 bit float; val 1 - val 0 == delta
  int q_quant = 0; // bits: 0 < quant <= 16
  int q_sequencep = 0; // bitflag


  List<int> quantlist = []; // map == 1: (int)(entries/dim) element column map
  // map == 2: list of dim*entries quantized entry vals

  int pack(Buffer opb){
    int i;
    bool ordered=false;

    opb.write0(0x564342, 24);
    opb.write0(dim, 16);
    opb.write0(entries, 24);

    for(i=1; i<entries; i++){
      if(lengthlist[i]<lengthlist[i-1])
        break;
    }
    if(i==entries)
      ordered=true;

    if(ordered){
      int count=0;
      opb.write0(1, 1); // ordered
      opb.write0(lengthlist[0]-1, 5); // 1 to 32

      for(i=1; i<entries; i++){
        int _this=lengthlist[i];
        int _last=lengthlist[i-1];
        if(_this>_last){
          for(int j=_last; j<_this; j++){
            opb.write0(i-count, Util.ilog(entries-count));
            count=i;
          }
        }
      }
      opb.write0(i-count, Util.ilog(entries-count));
    }
    else{
      opb.write0(0, 1); // unordered

      for(i=0; i<entries; i++){
        if(lengthlist[i]==0)
          break;
      }

      if(i==entries){
        opb.write0(0, 1); // no unused entries
        for(i=0; i<entries; i++){
          opb.write0(lengthlist[i]-1, 5);
        }
      }
      else{
        opb.write0(1, 1); // we have unused entries; thus we tag
        for(i=0; i<entries; i++){
          if(lengthlist[i]==0){
            opb.write0(0, 1);
          }
          else{
            opb.write0(1, 1);
            opb.write0(lengthlist[i]-1, 5);
          }
        }
      }
    }

    opb.write0(maptype, 4);
    switch(maptype){
      case 0:
      // no mapping
        break;
      case 1:
      case 2:
        if(quantlist==null){
          // no quantlist  error
          return (-1);
        }

        opb.write0(q_min, 32);
        opb.write0(q_delta, 32);
        opb.write0(q_quant-1, 4);
        opb.write0(q_sequencep, 1);

        {
          int quantvals=0;
          switch(maptype){
            case 1:
              quantvals=maptype1_quantvals();
              break;
            case 2:
              quantvals=entries*dim;
              break;
          }

          // quantized values
          for(i=0; i<quantvals; i++){
            opb.write0(quantlist[i].abs(), q_quant);
          }
        }
        break;
      default:
      // error case; we don't have any other map types now
        return (-1);
    }
    return (0);
  }

  int unpack(Buffer opb){
    int i;
    //memset(s,0,sizeof(static_codebook));

    // make sure alignment is correct
    if(opb.read0(24)!=0x564342){
      clear();
      return (-1);
    }

    dim=opb.read0(16);
    entries=opb.read0(24);
    if(entries==-1){
      clear();
      return (-1);
    }

    switch(opb.read0(1)){
      case 0:
        lengthlist = List.filled(entries,0);

        if(opb.read0(1)!=0){
          for(i=0; i<entries; i++){
            if(opb.read0(1)!=0){
              int num=opb.read0(5);
              if(num==-1){
                clear();
                return (-1);
              }
              lengthlist[i]=num+1;
            }
            else{
              lengthlist[i]=0;
            }
          }
        }
        else{
          for(i=0; i<entries; i++){
            int num=opb.read0(5);
            if(num==-1){
              clear();
              return (-1);
            }
            lengthlist[i]=num+1;
          }
        }
        break;
      case 1:
        {
          int length=opb.read0(5)+1;
          lengthlist = List.filled(entries,0);

          for(i=0; i<entries;){
            int num=opb.read0(Util.ilog(entries-i));
            if(num==-1){
              clear();
              return (-1);
            }
            for(int j=0; j<num; j++, i++){
              lengthlist[i]=length;
            }
            length++;
          }
        }
        break;
      default:
      // EOF
        return (-1);
    }

    // Do we have a mapping to unpack?
    switch((maptype=opb.read0(4))){
      case 0:
      // no mapping
        break;
      case 1:
      case 2:
        q_min=opb.read0(32);
        q_delta=opb.read0(32);
        q_quant=opb.read0(4)+1;
        q_sequencep=opb.read0(1);

        {
          int quantvals=0;
          switch(maptype){
            case 1:
              quantvals=maptype1_quantvals();
              break;
            case 2:
              quantvals=entries*dim;
              break;
          }

          // quantized values
          quantlist = List.filled(quantvals, 0);
          for(i=0; i<quantvals; i++){
            quantlist[i]=opb.read0(q_quant);
          }
          if(quantlist[quantvals-1]==-1){
            clear();
            return (-1);
          }
        }
        break;
      default:
        clear();
        return (-1);
    }
    return (0);
  }

  int maptype1_quantvals(){
    int vals=pow(entries, 1.0/dim).floor();

    while(true){
      int acc=1;
      int acc1=1;
      for(int i=0; i<dim; i++){
        acc*=vals;
        acc1*=vals+1;
      }
      if(acc<=entries&&acc1>entries){
        return (vals);
      }
      else{
        if(acc>entries){
          vals--;
        }
        else{
          vals++;
        }
      }
    }
  }

  void clear(){
  }

  List<double> unquantize(){

    if(maptype==1||maptype==2){
      int quantvals;
      double mindel=float32_unpack(q_min);
      double delta=float32_unpack(q_delta);
      List<double> r = List.filled(entries * dim, 0);

      switch(maptype){
        case 1:
          quantvals=maptype1_quantvals();
          for(int j=0; j<entries; j++){
            double last=0.0;
            int indexdiv=1;
            for(int k=0; k<dim; k++){
              int index=(j~/indexdiv)%quantvals;
              double val=quantlist[index].toDouble();
              val=val.abs()*delta+mindel+last;
              if(q_sequencep!=0)
                last=val;
              r[j*dim+k]=val;
              indexdiv*=quantvals;
            }
          }
          break;
        case 2:
          for(int j=0; j<entries; j++){
            double last=0.0;
            for(int k=0; k<dim; k++){
              double val=quantlist[j*dim+k].toDouble();
              val=val.abs()*delta+mindel+last;
              if(q_sequencep!=0)
                last=val;
              r[j*dim+k]=val;
            }
          }
      }
      return (r);
    }
    return [];
  }

  static final int VQ_FEXP=10;
  static final int VQ_FMAN=21;
  static final int VQ_FEXP_BIAS=768; // bias toward values smaller than 1.

  static int float32_pack(double val){
    int sign=0;
    int exp;
    int mant;
    if(val<0){
      sign=0x80000000;
      val=-val;
    }
    exp=(log(val)/log(2)).floor();
    mant=(pow(val, (VQ_FMAN-1)-exp)).round();
    exp=(exp+VQ_FEXP_BIAS)<<VQ_FMAN;
    return (sign|exp|mant);
  }

  static double float32_unpack(int val){
    double mant=(val&0x1fffff).toDouble();
    int exp=(val&0x7fe00000)>>VQ_FMAN;
    if((val&0x80000000)!=0)
      mant=-mant;
    return (ldexp(mant, exp-(VQ_FMAN-1)-VQ_FEXP_BIAS));
  }

  static double ldexp(double foo, int e){
    return (foo*pow(2, e));
  }
}
