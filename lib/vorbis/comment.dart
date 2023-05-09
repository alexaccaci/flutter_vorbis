import 'dart:typed_data';
import 'dart:convert';
import 'buffer.dart';
import 'ogg.dart';

class Comment {
  static Uint8List _vorbis = ascii.encode("vorbis");
  static Uint8List _vendor = ascii.encode("Xiphophorus libVorbis I 20000508");

  static final int OV_EIMPL = -130;

  // unlimited user comment fields.
  List<Uint8List>? user_comments;
  List<int>? comment_lengths;
  int comments = 0;
  Uint8List? vendor;

  void init() {
    user_comments = null;
    comments = 0;
    vendor = null;
  }

  void add(String comment) {
    add0(Uint8List.fromList(utf8.encode(comment)));
  }

  void add0(Uint8List comment) {
    List<Uint8List> foo = List.generate(comments + 2, (_) => Uint8List(0));
    if (user_comments != null) {
      //System.arraycopy(user_comments, 0, foo, 0, comments);
      foo.setAll(0, user_comments!);
    }
    user_comments = foo;

    List<int> goo = List.filled(comments + 2, 0);
    if (comment_lengths != null) {
      //System.arraycopy(comment_lengths, 0, goo, 0, comments);
      goo.setAll(0, comment_lengths!);
    }
    comment_lengths = goo;

    Uint8List bar = new Uint8List(comment.length + 1);
    //System.arraycopy(comment, 0, bar, 0, comment.length);
    bar.setAll(0, comment);
    user_comments![comments] = bar;
    comment_lengths![comments] = comment.length;
    comments++;
    user_comments![comments] = Uint8List(0);
  }

  void add_tag(String tag, String contents) {
    if (contents == null) contents = "";
    add(tag + "=" + contents);
  }

  static bool tagcompare(Uint8List s1, Uint8List s2, int n) {
    int c = 0;
    int u1, u2;
    while (c < n) {
      u1 = s1[c];
      u2 = s2[c];
      if ('Z'.codeUnits.first >= u1 && u1 >= 'A'.codeUnits.first)
        u1 = (u1 - 'A'.codeUnits.first + 'a'.codeUnits.first);
      if ('Z'.codeUnits.first >= u2 && u2 >= 'A'.codeUnits.first)
        u2 = u2 - 'A'.codeUnits.first + 'a'.codeUnits.first;
      if (u1 != u2) {
        return false;
      }
      c++;
    }
    return true;
  }

  String? query(String tag) {
    return query1(tag, 0);
  }

  String? query1(String tag, int count) {
    int foo = query0(Uint8List.fromList(utf8.encode(tag)), count);
    if (foo == -1) return null;
    Uint8List comment = user_comments![foo];
    for (int i = 0; i < comment_lengths![foo]; i++) {
      if (comment[i] == '='.codeUnits.first) {
        return utf8.decode(Uint8List.view(
            comment.buffer, i + 1, comment_lengths![foo] - (i + 1)));
      }
    }
    return null;
  }

  int query0(Uint8List tag, int count) {
    int i = 0;
    int found = 0;
    int fulltaglen = tag.length + 1;
    Uint8List fulltag = new Uint8List(fulltaglen);
    //System.arraycopy(tag, 0, fulltag, 0, tag.length);
    fulltag.setAll(0, tag);
    fulltag[tag.length] = '='.codeUnits.first;

    for (i = 0; i < comments; i++) {
      if (tagcompare(user_comments![i], fulltag, fulltaglen)) {
        if (count == found) {
          return i;
        } else {
          found++;
        }
      }
    }
    return -1;
  }

  int unpack(Buffer opb) {
    int vendorlen = opb.read0(32);
    if (vendorlen < 0) {
      clear();
      return (-1);
    }
    vendor = new Uint8List(vendorlen + 1);
    opb.read(vendor!, vendorlen);
    comments = opb.read0(32);
    if (comments < 0) {
      clear();
      return (-1);
    }
    user_comments = List.generate(comments + 1, (_) => Uint8List(0));
    comment_lengths = List.filled(comments + 1, 0);

    for (int i = 0; i < comments; i++) {
      int len = opb.read0(32);
      if (len < 0) {
        clear();
        return (-1);
      }
      comment_lengths![i] = len;
      user_comments![i] = new Uint8List(len + 1);
      opb.read(user_comments![i], len);
    }
    if (opb.read0(1) != 1) {
      clear();
      return (-1);
    }
    return (0);
  }

  int pack(Buffer opb) {
    // preamble
    opb.write0(0x03, 8);
    opb.write(_vorbis);

    // vendor
    opb.write0(_vendor.length, 32);
    opb.write(_vendor);

    // comments
    opb.write0(comments, 32);
    if (comments != 0) {
      for (int i = 0; i < comments; i++) {
        if (user_comments![i].length > 0) {
          opb.write0(comment_lengths![i], 32);
          opb.write(user_comments![i]);
        } else {
          opb.write0(0, 32);
        }
      }
    }
    opb.write0(1, 1);
    return (0);
  }

  int header_out(Packet op) {
    Buffer opb = new Buffer();
    opb.writeinit();

    if (pack(opb) != 0) return OV_EIMPL;

    op.packet_base = new Uint8List(opb.bytes());
    op.packet = 0;
    op.bytes = opb.bytes();
    //System.arraycopy(opb.buffer(), 0, op.packet_base, 0, op.bytes);
    op.packet_base!.setAll(0, opb.buffer!);
    op.b_o_s = 0;
    op.e_o_s = 0;
    op.granulepos = 0;
    return 0;
  }

  void clear() {
    for (int i = 0; i < comments; i++) user_comments![i] = Uint8List(0);
    user_comments = null;
    vendor = null;
  }

  String getVendor() {
    return utf8.decode(vendor!);
  }

  String? getComment(int i) {
    if (comments <= i) return null;
    return utf8.decode(user_comments![i]);
  }

  String toString() {
    String foo = "Vendor: " + utf8.decode(vendor!);
    for (int i = 0; i < comments; i++) {
      foo = foo + "\nComment: " + utf8.decode(user_comments![i]);
    }
    foo = foo + "\n";
    return foo;
  }
}
