import 'dart:typed_data';

class Packet {
  Uint8List? packet_base;
  int packet = 0;
  int bytes = 0;
  int b_o_s = 0;
  int e_o_s = 0;

  int granulepos = 0;
  int packetno = 0;
}

class Page {
  final _crc_lookup = [
    0x00000000,0x04C11DB7,0x09823B6E,0x0D4326D9,0x130476DC,0x17C56B6B,0x1A864DB2,0x1E475005,
    0x2608EDB8,0x22C9F00F,0x2F8AD6D6,0x2B4BCB61,0x350C9B64,0x31CD86D3,0x3C8EA00A,0x384FBDBD,
    0x4C11DB70,0x48D0C6C7,0x4593E01E,0x4152FDA9,0x5F15ADAC,0x5BD4B01B,0x569796C2,0x52568B75,
    0x6A1936C8,0x6ED82B7F,0x639B0DA6,0x675A1011,0x791D4014,0x7DDC5DA3,0x709F7B7A,0x745E66CD,
    0x9823B6E0,0x9CE2AB57,0x91A18D8E,0x95609039,0x8B27C03C,0x8FE6DD8B,0x82A5FB52,0x8664E6E5,
    0xBE2B5B58,0xBAEA46EF,0xB7A96036,0xB3687D81,0xAD2F2D84,0xA9EE3033,0xA4AD16EA,0xA06C0B5D,
    0xD4326D90,0xD0F37027,0xDDB056FE,0xD9714B49,0xC7361B4C,0xC3F706FB,0xCEB42022,0xCA753D95,
    0xF23A8028,0xF6FB9D9F,0xFBB8BB46,0xFF79A6F1,0xE13EF6F4,0xE5FFEB43,0xE8BCCD9A,0xEC7DD02D,
    0x34867077,0x30476DC0,0x3D044B19,0x39C556AE,0x278206AB,0x23431B1C,0x2E003DC5,0x2AC12072,
    0x128E9DCF,0x164F8078,0x1B0CA6A1,0x1FCDBB16,0x018AEB13,0x054BF6A4,0x0808D07D,0x0CC9CDCA,
    0x7897AB07,0x7C56B6B0,0x71159069,0x75D48DDE,0x6B93DDDB,0x6F52C06C,0x6211E6B5,0x66D0FB02,
    0x5E9F46BF,0x5A5E5B08,0x571D7DD1,0x53DC6066,0x4D9B3063,0x495A2DD4,0x44190B0D,0x40D816BA,
    0xACA5C697,0xA864DB20,0xA527FDF9,0xA1E6E04E,0xBFA1B04B,0xBB60ADFC,0xB6238B25,0xB2E29692,
    0x8AAD2B2F,0x8E6C3698,0x832F1041,0x87EE0DF6,0x99A95DF3,0x9D684044,0x902B669D,0x94EA7B2A,
    0xE0B41DE7,0xE4750050,0xE9362689,0xEDF73B3E,0xF3B06B3B,0xF771768C,0xFA325055,0xFEF34DE2,
    0xC6BCF05F,0xC27DEDE8,0xCF3ECB31,0xCBFFD686,0xD5B88683,0xD1799B34,0xDC3ABDED,0xD8FBA05A,
    0x690CE0EE,0x6DCDFD59,0x608EDB80,0x644FC637,0x7A089632,0x7EC98B85,0x738AAD5C,0x774BB0EB,
    0x4F040D56,0x4BC510E1,0x46863638,0x42472B8F,0x5C007B8A,0x58C1663D,0x558240E4,0x51435D53,
    0x251D3B9E,0x21DC2629,0x2C9F00F0,0x285E1D47,0x36194D42,0x32D850F5,0x3F9B762C,0x3B5A6B9B,
    0x0315D626,0x07D4CB91,0x0A97ED48,0x0E56F0FF,0x1011A0FA,0x14D0BD4D,0x19939B94,0x1D528623,
    0xF12F560E,0xF5EE4BB9,0xF8AD6D60,0xFC6C70D7,0xE22B20D2,0xE6EA3D65,0xEBA91BBC,0xEF68060B,
    0xD727BBB6,0xD3E6A601,0xDEA580D8,0xDA649D6F,0xC423CD6A,0xC0E2D0DD,0xCDA1F604,0xC960EBB3,
    0xBD3E8D7E,0xB9FF90C9,0xB4BCB610,0xB07DABA7,0xAE3AFBA2,0xAAFBE615,0xA7B8C0CC,0xA379DD7B,
    0x9B3660C6,0x9FF77D71,0x92B45BA8,0x9675461F,0x8832161A,0x8CF30BAD,0x81B02D74,0x857130C3,
    0x5D8A9099,0x594B8D2E,0x5408ABF7,0x50C9B640,0x4E8EE645,0x4A4FFBF2,0x470CDD2B,0x43CDC09C,
    0x7B827D21,0x7F436096,0x7200464F,0x76C15BF8,0x68860BFD,0x6C47164A,0x61043093,0x65C52D24,
    0x119B4BE9,0x155A565E,0x18197087,0x1CD86D30,0x029F3D35,0x065E2082,0x0B1D065B,0x0FDC1BEC,
    0x3793A651,0x3352BBE6,0x3E119D3F,0x3AD08088,0x2497D08D,0x2056CD3A,0x2D15EBE3,0x29D4F654,
    0xC5A92679,0xC1683BCE,0xCC2B1D17,0xC8EA00A0,0xD6AD50A5,0xD26C4D12,0xDF2F6BCB,0xDBEE767C,
    0xE3A1CBC1,0xE760D676,0xEA23F0AF,0xEEE2ED18,0xF0A5BD1D,0xF464A0AA,0xF9278673,0xFDE69BC4,
    0x89B8FD09,0x8D79E0BE,0x803AC667,0x84FBDBD0,0x9ABC8BD5,0x9E7D9662,0x933EB0BB,0x97FFAD0C,
    0xAFB010B1,0xAB710D06,0xA6322BDF,0xA2F33668,0xBCB4666D,0xB8757BDA,0xB5365D03,0xB1F740B4];

  static int crc_entry(int index) {
    int r = index << 24;
    for (int i = 0; i < 8; i++) {
      if ((r & 0x80000000) != 0) {
        r = (r << 1) ^ 0x04c11db7;
      } else {
        r <<= 1;
      }
    }
    return (r & 0xffffffff);
  }

  Uint8List? header_base;
  int header = 0;
  int header_len = 0;
  Uint8List? body_base;
  int body = 0;
  int body_len = 0;

  int version() {
    return header_base![header + 4] & 0xff;
  }

  int continued() {
    return (header_base![header + 5] & 0x01);
  }

  int bos() {
    return (header_base![header + 5] & 0x02);
  }

  int eos() {
    return (header_base![header + 5] & 0x04);
  }

  int granulepos() {
    int foo = header_base![header + 13] & 0xff;
    foo = (foo << 8) | (header_base![header + 12] & 0xff);
    foo = (foo << 8) | (header_base![header + 11] & 0xff);
    foo = (foo << 8) | (header_base![header + 10] & 0xff);
    foo = (foo << 8) | (header_base![header + 9] & 0xff);
    foo = (foo << 8) | (header_base![header + 8] & 0xff);
    foo = (foo << 8) | (header_base![header + 7] & 0xff);
    foo = (foo << 8) | (header_base![header + 6] & 0xff);
    return (foo);
  }

  int serialno() {
    return (header_base![header + 14] & 0xff) |
        ((header_base![header + 15] & 0xff) << 8) |
        ((header_base![header + 16] & 0xff) << 16) |
        ((header_base![header + 17] & 0xff) << 24);
  }

  int pageno() {
    return (header_base![header + 18] & 0xff) |
        ((header_base![header + 19] & 0xff) << 8) |
        ((header_base![header + 20] & 0xff) << 16) |
        ((header_base![header + 21] & 0xff) << 24);
  }

  void checksum() {
    int crc_reg = 0;

    for (int i = 0; i < header_len; i++) {
      crc_reg = (crc_reg << 8) ^
          _crc_lookup[
              ((crc_reg >> 24) & 0xff) ^ (header_base![header + i] & 0xff)];
    }
    for (int i = 0; i < body_len; i++) {
      crc_reg = (crc_reg << 8) ^
          _crc_lookup[((crc_reg >> 24) & 0xff) ^ (body_base![body + i] & 0xff)];
    }
    header_base![header + 22] = crc_reg & 0xff;
    header_base![header + 23] = (crc_reg >> 8) & 0xff;
    header_base![header + 24] = (crc_reg >> 16)& 0xff;
    header_base![header + 25] = (crc_reg >> 24) & 0xff;
  }

  Page copy() {
    return copy0(new Page());
  }

  Page copy0(Page p) {
    var tmp = new Uint8List(header_len);
    //System.arraycopy(header_base, header, tmp, 0, header_len);
    tmp.setAll(0, Uint8List.view(header_base!.buffer, header, header_len));
    p.header_len = header_len;
    p.header_base = tmp;
    p.header = 0;
    tmp = new Uint8List(body_len);
    //System.arraycopy(body_base, body, tmp, 0, body_len);
    tmp.setAll(0, Uint8List.view(body_base!.buffer, body, body_len));
    p.body_len = body_len;
    p.body_base = tmp;
    p.body = 0;
    return p;
  }
}

class StreamState {
  late Uint8List body_data; /* bytes from packet bodies */
  int body_storage = 0; /* storage elements allocated */
  int body_fill = 0; /* elements stored; fill mark */
  int body_returned = 0; /* elements of fill returned */

  List<int> lacing_vals = []; /* The values that will go to the segment table */
  List<int> granule_vals = []; /* pcm_pos values for headers */
  int lacing_storage = 0;
  int lacing_fill = 0;
  int lacing_packet = 0;
  int lacing_returned = 0;

  Uint8List header = new Uint8List(282);
  int header_fill = 0;

  int e_o_s = 0;
  int b_o_s = 0;
  int serialno = 0;
  int pageno = 0;
  int packetno = 0;
  int granulepos = 0;

  StreamState() {
    init0();
  }

  StreamState0(int serialno) {
    init(serialno);
  }

  void init0() {
    body_storage = 16 * 1024;
    body_data = new Uint8List(body_storage);
    lacing_storage = 1024;
    lacing_vals = List.filled(lacing_storage, 0);
    granule_vals = List.filled(lacing_storage, 0);
  }

  void init(int sn) {
    serialno = sn;
    print("Ogg init serialno $sn");
    if (body_data.length > 0) {
      init0();
    } else {
      for (int i = 0; i < body_data.length; i++) body_data[i] = 0;
      for (int i = 0; i < lacing_vals.length; i++) lacing_vals[i] = 0;
      for (int i = 0; i < granule_vals.length; i++) granule_vals[i] = 0;
    }
  }

  void clear() {
    body_data = Uint8List(0);
    lacing_vals = [];
    granule_vals = [];
  }

  void body_expand(int needed) {
    if (body_storage <= body_fill + needed) {
      body_storage += (needed + 1024);
      Uint8List foo = new Uint8List(body_storage);
      //System.arraycopy(body_data, 0, foo, 0, body_data.length);
      foo.setAll(0, Uint8List.view(body_data.buffer, 0, body_data.length));
      body_data = foo;
    }
  }

  void lacing_expand(int needed) {
    if (lacing_storage <= lacing_fill + needed) {
      lacing_storage += (needed + 32);
      List<int> foo = List.filled(lacing_storage,0);
      //System.arraycopy(lacing_vals, 0, foo, 0, lacing_vals.length);
      foo.setAll(0, lacing_vals);
      lacing_vals = foo;

      List<int> bar = List.filled(lacing_storage,0);
      //System.arraycopy(granule_vals, 0, bar, 0, granule_vals.length);
      bar.setAll(0, granule_vals);
      granule_vals = bar;
    }
  }

  /* submit data to the internal buffer of the framing engine */
  int packetin(Packet op) {
    int lacing_val = op.bytes ~/ 255 + 1;

    if (body_returned != 0) {
      body_fill -= body_returned;
      if (body_fill != 0) {
        //System.arraycopy(body_data, body_returned, body_data, 0, body_fill);
        body_data.setAll(
            0, Uint8List.view(body_data.buffer, body_returned, body_fill));
      }
      body_returned = 0;
    }

    body_expand(op.bytes);
    lacing_expand(lacing_val);

    //System.arraycopy(op.packet_base, op.packet, body_data, body_fill, op.bytes);
    body_data.setAll(
        body_fill, Uint8List.view(op.packet_base!.buffer, op.packet, op.bytes));
    body_fill += op.bytes;

    int j;
    for (j = 0; j < lacing_val - 1; j++) {
      lacing_vals[lacing_fill + j] = 255;
      granule_vals[lacing_fill + j] = granulepos;
    }
    lacing_vals[lacing_fill + j] = (op.bytes) % 255;
    granulepos = granule_vals[lacing_fill + j] = op.granulepos;

    lacing_vals[lacing_fill] |= 0x100;

    lacing_fill += lacing_val;

    packetno++;

    if (op.e_o_s != 0) e_o_s = 1;
    return (0);
  }

  int packetout(Packet op) {
    int ptr = lacing_returned;

    if (lacing_packet <= ptr) {
      return (0);
    }

    if ((lacing_vals[ptr] & 0x400) != 0) {
      lacing_returned++; // We lost sync

      packetno++;
      return (-1);
    }

    int size = lacing_vals[ptr] & 0xff;
    int bytes = 0;

    op.packet_base = body_data;
    op.packet = body_returned;
    op.e_o_s = lacing_vals[ptr] & 0x200; /* last packet of the stream? */
    op.b_o_s = lacing_vals[ptr] & 0x100; /* first packet of the stream? */
    bytes += size;

    while (size == 255) {
      int val = lacing_vals[++ptr];
      size = val & 0xff;
      if ((val & 0x200) != 0) op.e_o_s = 0x200;
      bytes += size;
    }

    op.packetno = packetno;
    //print(granule_vals);
    op.granulepos = granule_vals[ptr];
    op.bytes = bytes;

    body_returned += bytes;

    lacing_returned = ptr + 1;

    packetno++;
    return (1);
  }

  int pagein(Page og) {
    var header_base = og.header_base;
    int header = og.header;
    var body_base = og.body_base;
    int body = og.body;
    int bodysize = og.body_len;
    int segptr = 0;

    int version = og.version();
    int continued = og.continued();
    int bos = og.bos();
    int eos = og.eos();
    int granulepos = og.granulepos();
    //print("granulepos $granulepos");
    int _serialno = og.serialno();
    int _pageno = og.pageno();
    int segments = header_base![header + 26] & 0xff;

    int lr = lacing_returned;
    int br = body_returned;

    // body data
    if (br != 0) {
      body_fill -= br;
      if (body_fill != 0) {
        //System.arraycopy(body_data, br, body_data, 0, body_fill);
        body_data.setAll(0, Uint8List.view(body_data.buffer, br, body_fill));
      }
      body_returned = 0;
    }

    if (lr != 0) {
      // segment table
      if ((lacing_fill - lr) != 0) {
        //System.arraycopy(lacing_vals, lr, lacing_vals, 0, lacing_fill-lr);
        lacing_vals.setAll(0, lacing_vals.getRange(lr, lacing_fill));
        //System.arraycopy(granule_vals, lr, granule_vals, 0, lacing_fill-lr);
        granule_vals.setAll(0, granule_vals.getRange(lr, lacing_fill));
      }
      lacing_fill -= lr;
      lacing_packet -= lr;
      lacing_returned = 0;
    }

    // check the serial number
    //print("Ogg pagein version number $_serialno/$serialno");
    if (_serialno != serialno) {
      print("Error ogg pagein version number $_serialno != $serialno");
      return (-1);
    }
    if (version > 0) {
      print("Error ogg pagein positive version $version");
      return (-1);
    }

    lacing_expand(segments + 1);

    if (_pageno != pageno) {
      int i;

      for (i = lacing_packet; i < lacing_fill; i++) {
        body_fill -= lacing_vals[i] & 0xff;
        //System.out.println("??");
      }
      lacing_fill = lacing_packet;

      if (pageno != -1) {
        lacing_vals[lacing_fill++] = 0x400;
        lacing_packet++;
      }

      if (continued != 0) {
        bos = 0;
        for (; segptr < segments; segptr++) {
          int val = (header_base[header + 27 + segptr] & 0xff);
          body += val;
          bodysize -= val;
          if (val < 255) {
            segptr++;
            break;
          }
        }
      }
    }

    if (bodysize != 0) {
      body_expand(bodysize);
      //System.arraycopy(body_base, body, body_data, body_fill, bodysize);
      body_data.setAll(
          body_fill, Uint8List.view(body_base!.buffer, body, bodysize));
      body_fill += bodysize;
    }

    int saved = -1;
    while (segptr < segments) {
      int val = (header_base[header + 27 + segptr] & 0xff);
      lacing_vals[lacing_fill] = val;
      granule_vals[lacing_fill] = -1;

      if (bos != 0) {
        lacing_vals[lacing_fill] |= 0x100;
        bos = 0;
      }

      if (val < 255) saved = lacing_fill;

      lacing_fill++;
      segptr++;

      if (val < 255) lacing_packet = lacing_fill;
    }

    /* set the granulepos on the last pcmval of the last full packet */
    if (saved != -1) {
      granule_vals[saved] = granulepos;
    }

    if (eos != 0) {
      e_o_s = 1;
      if (lacing_fill > 0) lacing_vals[lacing_fill - 1] |= 0x200;
    }

    pageno = _pageno + 1;
    return (0);
  }

  int eof() {
    return e_o_s;
  }

  int reset() {
    body_fill = 0;
    body_returned = 0;

    lacing_fill = 0;
    lacing_packet = 0;
    lacing_returned = 0;

    header_fill = 0;

    e_o_s = 0;
    b_o_s = 0;
    pageno = -1;
    packetno = 0;
    granulepos = 0;
    return (0);
  }
}

class SyncState {
  Uint8List data = Uint8List(0);
  int storage = 0;
  int fill = 0;
  int returned = 0;

  int unsynced = 0;
  int headerbytes = 0;
  int bodybytes = 0;

  int clear() {
    data = Uint8List(0);
    return (0);
  }

  int buffer(int size) {
    if (returned != 0) {
      fill -= returned;
      if (fill > 0) {
        //System.arraycopy(data, returned, data, 0, fill);
        data.setAll(0, Uint8List.view(data.buffer, returned, fill));
      }
      returned = 0;
    }

    if (size > storage - fill) {
      int newsize = size + fill + 4096; // an extra page to be nice
      if (data.length > 0) {
        var foo = new Uint8List(newsize);
        //System.arraycopy(data, 0, foo, 0, data.length);
        foo.setAll(0, data);
        data = foo;
      } else {
        data = new Uint8List(newsize);
      }
      storage = newsize;
    }

    return (fill);
  }

  int wrote(int bytes) {
    if (fill + bytes > storage) return (-1);
    fill += bytes;
    return (0);
  }

  Page _pageseek = new Page();
  Uint8List _chksum = new Uint8List(4);

  int pageseek(Page og) {
    int page = returned;
    int next;
    int bytes = fill - returned;
    //print("bytes $bytes $headerbytes");

    if (headerbytes == 0) {
      if (bytes < 27) return (0); // not enough for a header

      if (data[page] != 'O'.codeUnits.first ||
          data[page + 1] != 'g'.codeUnits.first ||
          data[page + 2] != 'g'.codeUnits.first ||
          data[page + 3] != 'S'.codeUnits.first) {
        headerbytes = 0;
        bodybytes = 0;

        next = 0;
        for (int ii = 0; ii < bytes - 1; ii++) {
          if (data[page + 1 + ii] == 'O'.codeUnits.first) {
            next = page + 1 + ii;
            break;
          }
        }
        //next=memchr(page+1,'O',bytes-1);
        if (next == 0) next = fill;

        returned = next;
        //print("next $next page $page");
        return (-(next - page));
      }
      int _headerbytes = (data[page + 26] & 0xff) + 27;
      if (bytes < _headerbytes) return (0); // not enough for header + seg table

      for (int i = 0; i < (data[page + 26] & 0xff); i++) {
        bodybytes += (data[page + 27 + i] & 0xff);
      }
      headerbytes = _headerbytes;
    }

    if (bodybytes + headerbytes > bytes) return (0);

    //synchronized(chksum){

    //System.arraycopy(data, page+22, chksum, 0, 4);
    _chksum.setAll(0, Uint8List.view(data.buffer, page + 22, 4));
    data[page + 22] = 0;
    data[page + 23] = 0;
    data[page + 24] = 0;
    data[page + 25] = 0;

    // set up a temp page struct and recompute the checksum
    Page log = _pageseek;
    log.header_base = data;
    log.header = page;
    log.header_len = headerbytes;

    log.body_base = data;
    log.body = page + headerbytes;
    log.body_len = bodybytes;
    log.checksum();

    //print("checksum $page");
    //printBytes(_chksum, 4);
    //printBytes(Uint8List.view(data.buffer, page + 22, 4),4);
    // Compare
    if (_chksum[0] != data[page + 22] ||
        _chksum[1] != data[page + 23] ||
        _chksum[2] != data[page + 24] ||
        _chksum[3] != data[page + 25]) {

      //System.arraycopy(chksum, 0, data, page+22, 4);
      data.setAll(page + 22, _chksum);
      // Bad checksum. Lose sync */

      headerbytes = 0;
      bodybytes = 0;
      // search for possible capture
      next = 0;
      for (int ii = 0; ii < bytes - 1; ii++) {
        if (data[page + 1 + ii] == 'O'.codeUnits.first) {
          next = page + 1 + ii;
          break;
        }
      }
      //next=memchr(page+1,'O',bytes-1);
      if (next == 0) next = fill;
      returned = next;
      //print("returned $returned page $page next $next;");
      return (-(next - page));
    }
    //}synchronized

    // yes, have a whole page all ready to go
    page = returned;

    if (og != null) {
      og.header_base = data;
      og.header = page;
      og.header_len = headerbytes;
      og.body_base = data;
      og.body = page + headerbytes;
      og.body_len = bodybytes;
    }

    unsynced = 0;
    bytes = headerbytes + bodybytes;
    returned += bytes;
    headerbytes = 0;
    bodybytes = 0;
    //print("retturn $bytes");
    return bytes;
  }


  int pageout(Page og) {
    while (true) {
      int ret = pageseek(og);
      if (ret > 0) {
        // have a page
        //print("Ogg have a page");
        return (1);
      }
      if (ret == 0) {
        // need more data
        //print("Ogg need more data");
        return (0);
      }

      if (unsynced == 0) {
        unsynced = 1;
        //print("Ogg unsynced");
        return (-1);
      }
    }
  }

  int reset() {
    fill = 0;
    returned = 0;
    unsynced = 0;
    headerbytes = 0;
    bodybytes = 0;
    return (0);
  }

  int getDataOffset() {
    return returned;
  }

  int getBufferOffset() {
    return fill;
  }
}
