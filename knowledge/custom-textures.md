# Custom Textures for WoW Addons

## File Formats

WoW supports two formats for addon textures:

| Format | Notes |
|--------|-------|
| **TGA** | Preferred for addon development. Editable directly in any graphics editor. No special tools needed. |
| **BLP** | Blizzard's native format. Slightly more efficient at runtime but requires conversion tools. Overkill for most addon work. |

**Use TGA for addon icons and custom UI art.**

## Size Requirements

- Dimensions **must be powers of 2**: 8, 16, 32, 64, 128, 256, 512...
- Dimensions do **not** have to be square: 64x32 is fine, 64x40 is not.
- Images with transparency **must be saved as 32-bit** (BGRA / RGBA with alpha channel).
- WoW UI icons in the atlas are commonly **17x17** or **20x20** display pixels, but the texture file itself must be a power-of-2 size.

### Recommended sizes for button icons

| Use case | File size | Notes |
|----------|-----------|-------|
| Small button icon (17–20px display) | **32×32** | Power-of-2 closest to display size; plenty of detail |
| Medium button icon (~27px display) | **32×32** | Same; scale with `SetSize` in Lua |
| Larger panel art | 64×64 or 128×128 | As needed |

Our freemove button is 27×27 display pixels. A 32×32 TGA file is the correct choice.

## TGA Specification for WoW

- **Type**: Uncompressed true-color (type 2)
- **Bit depth**: 32 bits per pixel (BGRA channel order)
- **Origin**: WoW accepts both top-left and bottom-left origin (standard TGA uses bottom-left, but setting descriptor byte `0x28` sets top-left)
- **Alpha**: 8-bit alpha channel in the 4th byte of each pixel

### Minimal TGA header (18 bytes)

```
Offset  Size  Value   Description
0       1     0       ID length (no image ID)
1       1     0       Color map type (none)
2       1     2       Image type: uncompressed true-color
3       5     0...0   Color map spec (unused, all zeros)
8       2     0       X-origin
10      2     0       Y-origin
12      2     32      Width in pixels
14      2     32      Height in pixels
16      1     32      Bits per pixel
17      1     0x28    Image descriptor: top-left origin (bit5=1), 8 alpha bits (bits 0-3)
```

Pixel data follows immediately: `BGRA BGRA BGRA ...` row by row (top-to-bottom when using `0x28`).

### Python snippet to generate a TGA

```python
import struct

def write_tga(path, pixels, w, h):
    """pixels: list of rows, each row a list of (B, G, R, A) tuples"""
    header = struct.pack('<BBBHHBHHHHBB',
        0,    # id length
        0,    # no color map
        2,    # uncompressed true-color
        0, 0, 0,  # color map spec
        0, 0,     # x, y origin
        w, h,
        32,   # bits per pixel
        0x28, # top-left origin, 8 alpha bits
    )
    with open(path, 'wb') as f:
        f.write(header)
        for row in pixels:
            for (b, g, r, a) in row:
                f.write(struct.pack('BBBB', b, g, r, a))
```

## File Placement

Place textures inside the addon folder under a `textures/` subdirectory:

```
UIToolbox/
  textures/
    icon-pin.tga
    icon-foo.tga
  UIToolbox.toc
  Core.lua
  ...
```

**No TOC declaration is required.** Texture files are not Lua and do not need to be listed.

## Referencing Textures in Lua

Use the full virtual path with double backslashes. The file extension **can be omitted** — WoW will try both `.tga` and `.blp`:

```lua
local TEXTURE_PIN = "Interface\\AddOns\\UIToolbox\\textures\\icon-pin"

local tex = frame:CreateTexture(nil, "ARTWORK")
tex:SetTexture(TEXTURE_PIN)
tex:SetAllPoints(frame)
```

**Never include the file extension** in the path string — WoW resolves it automatically.

## Tinting and State

Because our icons are white/grayscale alpha-masked shapes, `SetVertexColor` is a great way to tint them for different states without extra texture files:

```lua
-- Active / enabled state
tex:SetVertexColor(1, 0.8, 0, 1)    -- golden yellow

-- Inactive / disabled state
tex:SetVertexColor(0.6, 0.6, 0.6, 0.8)  -- dim grey

-- Hover highlight
tex:SetVertexColor(1, 1, 0.4, 1)    -- bright yellow
```

The vertex color multiplies against the texture's pixel colors. A pure-white texture becomes whatever color you set.

## Our Icons

| File | Size | Description |
|------|------|-------------|
| `textures/icon-pin.tga` | 32×32 | Yellow push-pin, used on the FreeMove toggle button |

## Generation Script

The script `gen_pin_tga.py` at the workspace root generates all custom TGA icons.  
Run it whenever an icon needs to be regenerated:

```
python3 /home/aspieslechner/agent-workspaces/wow-addon/gen_pin_tga.py
```
