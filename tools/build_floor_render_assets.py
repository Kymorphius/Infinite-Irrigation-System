#!/usr/bin/env python3
"""Build the PZ texture pack and tile definition used by floor-layer pipes."""

from __future__ import annotations

import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "Contents/mods/WaterPipes-IrrigationSystems/42"
TEXTURES = MOD / "media/textures"
PACK = MOD / "media/texturepacks/infinite_irrigation_pipes.pack"
TILEDEF = MOD / "media/infinite_irrigation_pipe_tiledefinitions.tiles"

IRRIGATION_SOURCE_NAMES = (
    "Item_PipeSE.png",
    "Item_PipeNorth.png",
    "Item_PipeCross.png",
    "Item_PipeCornerNE.png",
    "Item_PipeCornerNW.png",
    "Item_PipeCornerSE.png",
    "Item_PipeCornerSW.png",
    "Item_PipeTN.png",
    "Item_PipeTS.png",
    "Item_PipeTE.png",
    "Item_PipeTW.png",
)
VERTICAL_SOURCE_NAMES = (
    "Item_PipeVerticalN.png",
    "Item_PipeVerticalE.png",
    "Item_PipeVerticalS.png",
    "Item_PipeVerticalW.png",
)
SOURCE_NAMES = (
    IRRIGATION_SOURCE_NAMES
    + IRRIGATION_SOURCE_NAMES
    + VERTICAL_SOURCE_NAMES
    + VERTICAL_SOURCE_NAMES
)
TILESET = "infinite_irrigation_pipes_01"
SUPPLY_PIPE_START = len(IRRIGATION_SOURCE_NAMES)
SUPPLY_PIPE_END = SUPPLY_PIPE_START + len(IRRIGATION_SOURCE_NAMES)
VERTICAL_IRRIGATION_INDEX = SUPPLY_PIPE_END
VERTICAL_IRRIGATION_END = VERTICAL_IRRIGATION_INDEX + len(VERTICAL_SOURCE_NAMES)
VERTICAL_SUPPLY_INDEX = VERTICAL_IRRIGATION_END
VERTICAL_SUPPLY_END = VERTICAL_SUPPLY_INDEX + len(VERTICAL_SOURCE_NAMES)


def u32(value: int) -> bytes:
    return struct.pack("<I", value)


def pack_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return u32(len(encoded)) + encoded


def png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("source texture is not a PNG")
    return struct.unpack(">II", data[16:24])


def build_texture_pack() -> None:
    pages: list[bytes] = []
    for index, filename in enumerate(SOURCE_NAMES):
        png = (TEXTURES / filename).read_bytes()
        width, height = png_size(png)
        if (width, height) != (128, 256):
            raise ValueError(f"{filename}: expected 128x256, got {width}x{height}")

        sprite_name = f"{TILESET}_{index}"
        page = bytearray()
        page += pack_string(f"infinite_irrigation_pipes{index}")
        page += u32(1)  # one sprite on this page
        page += u32(1)  # page has alpha
        page += pack_string(sprite_name)
        page += struct.pack("<8I", 0, 0, width, height, 0, 0, width, height)
        page += u32(len(png))
        page += png
        pages.append(bytes(page))

    PACK.parent.mkdir(parents=True, exist_ok=True)
    PACK.write_bytes(b"PZPK" + u32(1) + u32(len(pages)) + b"".join(pages))


def line(value: str) -> bytes:
    return value.encode("utf-8") + b"\n"


def build_tile_definition() -> None:
    width, height = 8, 4
    tile_count = width * height
    data = bytearray(b"tdef")
    data += u32(1)  # format version
    data += u32(1)  # one tileset
    data += line(TILESET)
    data += line(f"{TILESET}.png")
    data += u32(width) + u32(height) + u32(1) + u32(tile_count)
    for index in range(tile_count):
        if SUPPLY_PIPE_START <= index < SUPPLY_PIPE_END:
            properties = (
                ("RenderLayer", "Floor"),
                ("waterAmount", "10000"),
                ("waterMaxAmount", "10000"),
                ("waterPiped", ""),
            )
            data += u32(len(properties))
            for key, value in properties:
                data += line(key) + line(value)
        elif index < len(IRRIGATION_SOURCE_NAMES):
            data += u32(1) + line("RenderLayer") + line("Floor")
        elif VERTICAL_SUPPLY_INDEX <= index < VERTICAL_SUPPLY_END:
            properties = (
                ("waterAmount", "10000"),
                ("waterMaxAmount", "10000"),
                ("waterPiped", ""),
            )
            data += u32(len(properties))
            for key, value in properties:
                data += line(key) + line(value)
        else:
            data += u32(0)
    TILEDEF.write_bytes(data)


if __name__ == "__main__":
    build_texture_pack()
    build_tile_definition()
    print(f"Built {PACK.relative_to(ROOT)}")
    print(f"Built {TILEDEF.relative_to(ROOT)}")
