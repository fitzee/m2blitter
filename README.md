# m2blitter

A software blitter written in Modula-2 (PIM4), modelled on the Amiga's custom blitter hardware. It operates on 8-bit indexed-colour pixel buffers and implements the same minterm-based logic the Amiga uses to combine source and destination data.

## What it does

The core `Blitter` module evaluates an 8-bit minterm truth table across three inputs (A, B, C/destination), exactly like the Amiga blitter's logic function unit. This lets you express any boolean combination of sources and destination in a single blit call.

On top of that, it provides higher-level operations:

- **BlitOp** - General minterm blit with two PixBuf sources and a read-modify-write destination.
- **BlitOpMask** - Same, but the A channel is a packed 1-bit mask instead of a PixBuf.
- **MaskedBlit** - Sprite-through-mask compositing (minterm 0xCA).
- **CopyBlit** - Straight rectangle copy (minterm 0xCC).
- **TransparentBlit** - Copy with a transparent colour key.
- **ShadowBlit / ShadowBlitRGBA** - Masked overlay using an 8-bit mask PixBuf, with clipping.

The `BlitMask` module handles 1-bit packed mask creation, manipulation, and boolean combination (AND, OR, invert).

## How it compares to the Amiga blitter

The Amiga blitter is a DMA-driven hardware unit on the custom Agnus/Alice chip. It reads from up to three source channels (A, B, C) in chip RAM, applies a minterm logic function, and writes the result back, all without CPU involvement. It also handles shifting, masking first/last words, and modulos for non-contiguous memory layouts. Line drawing and area fill are built into the hardware too.

This project reproduces the minterm logic faithfully but runs it in software, pixel by pixel, on 8-bit indexed buffers rather than on bitplanes via DMA. The key differences:

- **No DMA.** The Amiga blitter operates independently of the CPU, reading and writing chip RAM through its own bus access. This implementation is CPU-driven.
- **Pixel-oriented, not bitplane-oriented.** The Amiga works on planar bitmap data (one bit per plane per pixel). This blitter works on chunky 8-bit pixels and applies the minterm across all 8 bits at once.
- **No barrel shifter or word masking.** The Amiga blitter can shift A and B sources by 0-15 bits and mask the first/last words of each row for sub-word alignment. This implementation operates at whole-pixel granularity.
- **No line draw or area fill modes.** The Amiga blitter has dedicated hardware modes for Bresenham line drawing and area fill. Those are not implemented here.
- **No modulos.** The Amiga uses per-channel modulo values to skip between non-contiguous rows in memory. This implementation uses PixBuf accessors with explicit coordinates instead.

The minterm truth table itself (the 256 possible logic functions of three inputs) works identically.

## Building

Requires the mx Modula-2 compiler and the `m2gfx` dependency. The `m2.toml` defines the project configuration. The mx compiler transpiles the Modula-2 source to C (`Blitter.c` is the generated output).

## Files

```
src/Blitter.def    - Blitter interface (minterm constants, procedure signatures)
src/Blitter.mod    - Blitter implementation
src/BlitMask.def   - 1-bit mask interface
src/BlitMask.mod   - 1-bit mask implementation
src/Blitter.c      - Generated C output from mx compiler (do not edit)
m2.toml            - Project configuration
```

## License

Copyright (c) 2026, Matt Fitzgerald. MIT License.
