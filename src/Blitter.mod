IMPLEMENTATION MODULE Blitter;

FROM SYSTEM IMPORT ADDRESS;
FROM PixBuf IMPORT PBuf, Width, Height, GetPix, SetPix;
FROM GfxBridge IMPORT gfx_pb_pixel_ptr, gfx_buf_get, gfx_buf_set,
                      gfx_pb_rgba_set32;
FROM PixBuf IMPORT PalR, PalG, PalB;

(* General minterm evaluation: D = f(A, B, C) applied bitwise.
   Uses mx builtins BAND, BOR, BNOT for native bitwise ops. *)

PROCEDURE EvalMinterm(a, b, c, mt: CARDINAL): CARDINAL;
VAR na, nb, nc, result: CARDINAL;
BEGIN
  na := BAND(BNOT(a), 0FFH);
  nb := BAND(BNOT(b), 0FFH);
  nc := BAND(BNOT(c), 0FFH);
  result := 0;
  IF BAND(mt,   1) # 0 THEN result := BOR(result, BAND(BAND(na, nb), nc)) END;
  IF BAND(mt,   2) # 0 THEN result := BOR(result, BAND(BAND(na, nb), c))  END;
  IF BAND(mt,   4) # 0 THEN result := BOR(result, BAND(BAND(na, b), nc))  END;
  IF BAND(mt,   8) # 0 THEN result := BOR(result, BAND(BAND(na, b), c))   END;
  IF BAND(mt,  16) # 0 THEN result := BOR(result, BAND(BAND(a, nb), nc))  END;
  IF BAND(mt,  32) # 0 THEN result := BOR(result, BAND(BAND(a, nb), c))   END;
  IF BAND(mt,  64) # 0 THEN result := BOR(result, BAND(BAND(a, b), nc))   END;
  IF BAND(mt, 128) # 0 THEN result := BOR(result, BAND(BAND(a, b), c))    END;
  RETURN BAND(result, 0FFH)
END EvalMinterm;

(* === Core blit operations === *)

PROCEDURE BlitOp(srcA, srcB, dst: PBuf;
                 ax, ay, bx, by, dx, dy, w, h: INTEGER;
                 minterm: INTEGER);
VAR row, col, a, b, c: INTEGER;
BEGIN
  IF dst = NIL THEN RETURN END;
  FOR row := 0 TO h - 1 DO
    FOR col := 0 TO w - 1 DO
      IF srcA # NIL THEN
        a := GetPix(srcA, ax + col, ay + row)
      ELSE
        a := 0
      END;
      IF srcB # NIL THEN
        b := GetPix(srcB, bx + col, by + row)
      ELSE
        b := 0
      END;
      c := GetPix(dst, dx + col, dy + row);
      SetPix(dst, dx + col, dy + row,
             INTEGER(EvalMinterm(CARDINAL(a), CARDINAL(b),
                                CARDINAL(c), CARDINAL(minterm))))
    END
  END
END BlitOp;

PROCEDURE BlitOpMask(maskA: ADDRESS; maskStride: INTEGER;
                     srcB, dst: PBuf;
                     mx, my, bx, by, dx, dy, w, h: INTEGER;
                     minterm: INTEGER);
VAR row, col, b, c, bitPos, byteVal: INTEGER;
    a: CARDINAL;
BEGIN
  IF dst = NIL THEN RETURN END;
  FOR row := 0 TO h - 1 DO
    FOR col := 0 TO w - 1 DO
      (* Read 1-bit mask, expand to 0x00 or 0xFF *)
      bitPos := mx + col;
      byteVal := gfx_buf_get(maskA, (my + row) * maskStride + bitPos DIV 8);
      IF BAND(CARDINAL(byteVal), SHL(1, 7 - CARDINAL(bitPos MOD 8))) # 0 THEN
        a := 0FFH
      ELSE
        a := 0
      END;
      IF srcB # NIL THEN
        b := GetPix(srcB, bx + col, by + row)
      ELSE
        b := 0
      END;
      c := GetPix(dst, dx + col, dy + row);
      SetPix(dst, dx + col, dy + row,
             INTEGER(EvalMinterm(a, CARDINAL(b), CARDINAL(c),
                                CARDINAL(minterm))))
    END
  END
END BlitOpMask;

PROCEDURE MaskedBlit(maskA: ADDRESS; maskStride: INTEGER;
                     sprite, dst: PBuf;
                     mx, my, sx, sy, dx, dy, w, h: INTEGER);
BEGIN
  BlitOpMask(maskA, maskStride, sprite, dst,
             mx, my, sx, sy, dx, dy, w, h, MtMasked)
END MaskedBlit;

PROCEDURE CopyBlit(src, dst: PBuf;
                   sx, sy, dx, dy, w, h: INTEGER);
VAR row, col: INTEGER;
BEGIN
  IF (src = NIL) OR (dst = NIL) THEN RETURN END;
  FOR row := 0 TO h - 1 DO
    FOR col := 0 TO w - 1 DO
      SetPix(dst, dx + col, dy + row,
             GetPix(src, sx + col, sy + row))
    END
  END
END CopyBlit;

PROCEDURE TransparentBlit(src, dst: PBuf;
                          sx, sy, dx, dy, w, h: INTEGER;
                          transIdx: INTEGER);
VAR row, col, px: INTEGER;
BEGIN
  IF (src = NIL) OR (dst = NIL) THEN RETURN END;
  FOR row := 0 TO h - 1 DO
    FOR col := 0 TO w - 1 DO
      px := GetPix(src, sx + col, sy + row);
      IF px # transIdx THEN
        SetPix(dst, dx + col, dy + row, px)
      END
    END
  END
END TransparentBlit;

PROCEDURE ClearRect(dst: PBuf; x, y, w, h: INTEGER);
VAR row, col: INTEGER;
BEGIN
  IF dst = NIL THEN RETURN END;
  FOR row := 0 TO h - 1 DO
    FOR col := 0 TO w - 1 DO
      SetPix(dst, x + col, y + row, 0)
    END
  END
END ClearRect;

PROCEDURE OverlayBlit(fg, dst: PBuf;
                      sx, sy, dx, dy, w, h: INTEGER);
BEGIN
  TransparentBlit(fg, dst, sx, sy, dx, dy, w, h, 0)
END OverlayBlit;

PROCEDURE ShadowBlit(src: PBuf; mask: PBuf;
                     sx, sy: INTEGER;
                     maskX, maskY: INTEGER;
                     dst: PBuf;
                     dx, dy, w, h: INTEGER);
VAR row, col, px, mx: INTEGER;
    dw, dh: INTEGER;
    clx, cly, crx, cry: INTEGER;
BEGIN
  IF (src = NIL) OR (mask = NIL) OR (dst = NIL) THEN RETURN END;
  dw := Width(dst); dh := Height(dst);

  (* Clip to destination bounds *)
  clx := 0; cly := 0; crx := w; cry := h;
  IF dx < 0 THEN clx := -dx; dx := 0 END;
  IF dy < 0 THEN cly := -dy; dy := 0 END;
  IF dx + (crx - clx) > dw THEN crx := clx + dw - dx END;
  IF dy + (cry - cly) > dh THEN cry := cly + dh - dy END;

  FOR row := cly TO cry - 1 DO
    FOR col := clx TO crx - 1 DO
      mx := GetPix(mask, maskX + col, maskY + row);
      IF mx # 0 THEN
        px := GetPix(src, sx + col, sy + row);
        SetPix(dst, dx + col - clx, dy + row - cly, px)
      END
    END
  END
END ShadowBlit;

PROCEDURE ShadowBlitRGBA(src: PBuf; mask: PBuf;
                         sx, sy: INTEGER;
                         maskX, maskY: INTEGER;
                         dst: PBuf;
                         dx, dy, w, h: INTEGER);
VAR row, col, px, mx: INTEGER;
    dw, dh: INTEGER;
    clx, cly, crx, cry: INTEGER;
    r, g, b: INTEGER;
    rgba: CARDINAL;
    dstPtr: ADDRESS;
    dstOff: INTEGER;
BEGIN
  IF (src = NIL) OR (mask = NIL) OR (dst = NIL) THEN RETURN END;
  dw := Width(dst); dh := Height(dst);

  clx := 0; cly := 0; crx := w; cry := h;
  IF dx < 0 THEN clx := -dx; dx := 0 END;
  IF dy < 0 THEN cly := -dy; dy := 0 END;
  IF dx + (crx - clx) > dw THEN crx := clx + dw - dx END;
  IF dy + (cry - cly) > dh THEN cry := cly + dh - dy END;

  FOR row := cly TO cry - 1 DO
    FOR col := clx TO crx - 1 DO
      mx := GetPix(mask, maskX + col, maskY + row);
      IF mx # 0 THEN
        px := GetPix(src, sx + col, sy + row);
        (* Look up RGB from source's own palette *)
        r := PalR(src, px);
        g := PalG(src, px);
        b := PalB(src, px);
        (* Write RGBA directly to dst's rgba buffer:
           format is RGBA8888 = R<<24 | G<<16 | B<<8 | A *)
        rgba := BOR(BOR(BOR(SHL(CARDINAL(r), 24),
                             SHL(CARDINAL(g), 16)),
                         SHL(CARDINAL(b), 8)),
                    0FFH);
        dstOff := (dy + row - cly) * dw + (dx + col - clx);
        gfx_pb_rgba_set32(dst, dstOff, INTEGER(rgba))
      END
    END
  END
END ShadowBlitRGBA;

END Blitter.
