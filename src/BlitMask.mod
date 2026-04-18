IMPLEMENTATION MODULE BlitMask;

FROM SYSTEM IMPORT ADDRESS;
FROM PixBuf IMPORT PBuf, GetPix;
FROM GfxBridge IMPORT gfx_alloc, gfx_dealloc,
                      gfx_buf_get, gfx_buf_set;

PROCEDURE Create(w, h: INTEGER; VAR m: Mask);
VAR size: INTEGER;
BEGIN
  m.w := w;
  m.h := h;
  m.stride := (w + 7) DIV 8;
  size := m.stride * h;
  m.bits := gfx_alloc(size);
  Clear(m)
END Create;

PROCEDURE Free(VAR m: Mask);
BEGIN
  IF m.bits # NIL THEN
    gfx_dealloc(m.bits);
    m.bits := NIL
  END;
  m.w := 0; m.h := 0; m.stride := 0
END Free;

PROCEDURE Clear(VAR m: Mask);
VAR i, size: INTEGER;
BEGIN
  size := m.stride * m.h;
  FOR i := 0 TO size - 1 DO
    gfx_buf_set(m.bits, i, 0)
  END
END Clear;

PROCEDURE Fill(VAR m: Mask);
VAR i, size: INTEGER;
BEGIN
  size := m.stride * m.h;
  FOR i := 0 TO size - 1 DO
    gfx_buf_set(m.bits, i, 255)
  END
END Fill;

PROCEDURE ByteIdx(VAR m: Mask; x, y: INTEGER): INTEGER;
BEGIN
  RETURN y * m.stride + x DIV 8
END ByteIdx;

PROCEDURE BitMask(x: INTEGER): INTEGER;
BEGIN
  (* MSB first: bit 7 for x MOD 8 = 0 *)
  CASE x MOD 8 OF
    0: RETURN 128 |
    1: RETURN 64  |
    2: RETURN 32  |
    3: RETURN 16  |
    4: RETURN 8   |
    5: RETURN 4   |
    6: RETURN 2   |
    7: RETURN 1
  ELSE
    RETURN 0
  END
END BitMask;

PROCEDURE SetBit(VAR m: Mask; x, y: INTEGER);
VAR idx, val, bit: INTEGER;
BEGIN
  IF (x < 0) OR (x >= m.w) OR (y < 0) OR (y >= m.h) THEN RETURN END;
  idx := ByteIdx(m, x, y);
  bit := BitMask(x);
  val := gfx_buf_get(m.bits, idx);
  (* OR the bit in *)
  IF (val DIV bit) MOD 2 = 0 THEN
    gfx_buf_set(m.bits, idx, val + bit)
  END
END SetBit;

PROCEDURE ClearBit(VAR m: Mask; x, y: INTEGER);
VAR idx, val, bit: INTEGER;
BEGIN
  IF (x < 0) OR (x >= m.w) OR (y < 0) OR (y >= m.h) THEN RETURN END;
  idx := ByteIdx(m, x, y);
  bit := BitMask(x);
  val := gfx_buf_get(m.bits, idx);
  IF (val DIV bit) MOD 2 = 1 THEN
    gfx_buf_set(m.bits, idx, val - bit)
  END
END ClearBit;

PROCEDURE TestBit(VAR m: Mask; x, y: INTEGER): BOOLEAN;
VAR idx, val, bit: INTEGER;
BEGIN
  IF (x < 0) OR (x >= m.w) OR (y < 0) OR (y >= m.h) THEN RETURN FALSE END;
  idx := ByteIdx(m, x, y);
  bit := BitMask(x);
  val := gfx_buf_get(m.bits, idx);
  RETURN (val DIV bit) MOD 2 = 1
END TestBit;

PROCEDURE FromPixBuf(pb: PBuf; x, y, w, h: INTEGER;
                     transIdx: INTEGER; VAR m: Mask);
VAR px, py: INTEGER;
BEGIN
  Create(w, h, m);
  FOR py := 0 TO h - 1 DO
    FOR px := 0 TO w - 1 DO
      IF GetPix(pb, x + px, y + py) # transIdx THEN
        SetBit(m, px, py)
      END
    END
  END
END FromPixBuf;

PROCEDURE FromRaw(data: ADDRESS; frameW, frameH, frameIdx: INTEGER;
                  VAR m: Mask);
VAR srcStride, srcOff, dstOff, row, size: INTEGER;
BEGIN
  srcStride := (frameW + 7) DIV 8;
  Create(frameW, frameH, m);
  srcOff := frameIdx * frameH * srcStride;
  dstOff := 0;
  FOR row := 0 TO frameH - 1 DO
    size := srcStride;
    WHILE size > 0 DO
      gfx_buf_set(m.bits, dstOff,
                  gfx_buf_get(data, srcOff));
      INC(srcOff);
      INC(dstOff);
      DEC(size)
    END
  END
END FromRaw;

PROCEDURE CombineAnd(VAR dst, src: Mask;
                     dx, dy, sx, sy, w, h: INTEGER);
VAR px, py: INTEGER;
    dSet, sSet: BOOLEAN;
BEGIN
  FOR py := 0 TO h - 1 DO
    FOR px := 0 TO w - 1 DO
      dSet := TestBit(dst, dx + px, dy + py);
      sSet := TestBit(src, sx + px, sy + py);
      IF dSet AND (NOT sSet) THEN
        ClearBit(dst, dx + px, dy + py)
      END
    END
  END
END CombineAnd;

PROCEDURE CombineOr(VAR dst, src: Mask;
                    dx, dy, sx, sy, w, h: INTEGER);
VAR px, py: INTEGER;
BEGIN
  FOR py := 0 TO h - 1 DO
    FOR px := 0 TO w - 1 DO
      IF TestBit(src, sx + px, sy + py) THEN
        SetBit(dst, dx + px, dy + py)
      END
    END
  END
END CombineOr;

PROCEDURE Invert(VAR m: Mask; x, y, w, h: INTEGER);
VAR px, py: INTEGER;
BEGIN
  FOR py := y TO y + h - 1 DO
    FOR px := x TO x + w - 1 DO
      IF TestBit(m, px, py) THEN
        ClearBit(m, px, py)
      ELSE
        SetBit(m, px, py)
      END
    END
  END
END Invert;

END BlitMask.
