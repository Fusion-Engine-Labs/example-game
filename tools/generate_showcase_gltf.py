#!/usr/bin/env python3
"""Generate the small, dependency-free glTF used by the backpack showcase."""

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MESH_DIR = ROOT / "assets" / "meshes"
BIN_PATH = MESH_DIR / "showcase.bin"
GLTF_PATH = MESH_DIR / "showcase.gltf"

blob = bytearray()
buffer_views = []
accessors = []


def align(alignment=4):
    while len(blob) % alignment:
        blob.append(0)


def accessor(values, component_type, value_type, target, include_bounds=False):
    align()
    offset = len(blob)
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[value_type]
    fmt = {5123: "H", 5126: "f"}[component_type]
    flat = [component for value in values for component in (value if isinstance(value, tuple) else (value,))]
    blob.extend(struct.pack("<" + fmt * len(flat), *flat))
    view_index = len(buffer_views)
    buffer_views.append({
        "buffer": 0,
        "byteOffset": offset,
        "byteLength": len(blob) - offset,
        "target": target,
    })
    result = {
        "bufferView": view_index,
        "componentType": component_type,
        "count": len(values),
        "type": value_type,
    }
    if include_bounds:
        result["min"] = [min(value[i] for value in values) for i in range(components)]
        result["max"] = [max(value[i] for value in values) for i in range(components)]
    accessors.append(result)
    return len(accessors) - 1


def empty_geometry():
    return {"positions": [], "normals": [], "uvs": [], "indices": []}


def merge(*geometries):
    result = empty_geometry()
    for geometry in geometries:
        base = len(result["positions"])
        result["positions"].extend(geometry["positions"])
        result["normals"].extend(geometry["normals"])
        result["uvs"].extend(geometry["uvs"])
        result["indices"].extend(base + index for index in geometry["indices"])
    return result


def box(center, size):
    cx, cy, cz = center
    x, y, z = (dimension / 2 for dimension in size)
    faces = [
        (((-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)), (0, 0, 1)),
        (((x, -y, -z), (-x, -y, -z), (-x, y, -z), (x, y, -z)), (0, 0, -1)),
        (((x, -y, z), (x, -y, -z), (x, y, -z), (x, y, z)), (1, 0, 0)),
        (((-x, -y, -z), (-x, -y, z), (-x, y, z), (-x, y, -z)), (-1, 0, 0)),
        (((-x, y, z), (x, y, z), (x, y, -z), (-x, y, -z)), (0, 1, 0)),
        (((-x, -y, -z), (x, -y, -z), (x, -y, z), (-x, -y, z)), (0, -1, 0)),
    ]
    geometry = empty_geometry()
    for vertices, normal in faces:
        base = len(geometry["positions"])
        geometry["positions"].extend((cx + vx, cy + vy, cz + vz) for vx, vy, vz in vertices)
        geometry["normals"].extend([normal] * 4)
        geometry["uvs"].extend(((0, 0), (1, 0), (1, 1), (0, 1)))
        geometry["indices"].extend((base, base + 1, base + 2, base, base + 2, base + 3))
    return geometry


def quad(width, height):
    x, y = width / 2, height / 2
    return {
        "positions": [(-x, -y, 0), (x, -y, 0), (x, y, 0), (-x, y, 0)],
        "normals": [(0, 0, 1)] * 4,
        "uvs": [(0, 1), (1, 1), (1, 0), (0, 0)],
        "indices": [0, 1, 2, 0, 2, 3],
    }


def cylinder(radius, height, center_y, segments=16):
    geometry = empty_geometry()
    half = height / 2
    for i in range(segments + 1):
        angle = i * math.tau / segments
        x, z = math.cos(angle) * radius, math.sin(angle) * radius
        u = i / segments
        geometry["positions"].extend(((x, center_y - half, z), (x, center_y + half, z)))
        geometry["normals"].extend(((math.cos(angle), 0, math.sin(angle)),) * 2)
        geometry["uvs"].extend(((u, 0), (u, 1)))
    for i in range(segments):
        base = i * 2
        geometry["indices"].extend((base, base + 2, base + 3, base, base + 3, base + 1))

    for normal, y, reverse in ((1, center_y + half, False), (-1, center_y - half, True)):
        center_index = len(geometry["positions"])
        geometry["positions"].append((0, y, 0))
        geometry["normals"].append((0, normal, 0))
        geometry["uvs"].append((0.5, 0.5))
        ring_start = len(geometry["positions"])
        for i in range(segments):
            angle = i * math.tau / segments
            x, z = math.cos(angle) * radius, math.sin(angle) * radius
            geometry["positions"].append((x, y, z))
            geometry["normals"].append((0, normal, 0))
            geometry["uvs"].append((x / radius * 0.5 + 0.5, z / radius * 0.5 + 0.5))
        for i in range(segments):
            current = ring_start + i
            following = ring_start + (i + 1) % segments
            triangle = (center_index, following, current) if reverse else (center_index, current, following)
            geometry["indices"].extend(triangle)
    return geometry


def primitive(geometry, material):
    return {
        "attributes": {
            "POSITION": accessor(geometry["positions"], 5126, "VEC3", 34962, True),
            "NORMAL": accessor(geometry["normals"], 5126, "VEC3", 34962),
            "TEXCOORD_0": accessor(geometry["uvs"], 5126, "VEC2", 34962),
        },
        "indices": accessor(geometry["indices"], 5123, "SCALAR", 34963),
        "material": material,
    }


stage_wood = merge(
    box((0, -1.55, 0), (6.7, 0.34, 1.55)),
    box((-3.55, -0.30, 0.05), (0.16, 2.25, 0.18)),
    box((-3.15, 0.58, 0.05), (0.95, 0.18, 0.18)),
)
stage_slate = merge(
    box((0, -1.54, 0.80), (6.9, 0.30, 0.10)),
    box((3.00, 1.25, 0.05), (2.00, 0.13, 0.16)),
    box((3.00, -0.12, 0.05), (2.00, 0.13, 0.16)),
    box((2.03, 0.57, 0.05), (0.13, 1.50, 0.16)),
    box((3.97, 0.57, 0.05), (0.13, 1.50, 0.16)),
)
stage_orange = merge(
    box((-3.15, 0.58, 0.16), (0.45, 0.42, 0.08)),
    box((-3.15, 0.58, 0.22), (0.14, 0.64, 0.06)),
)
ground = box((0, -1.86, -0.55), (8.4, 0.28, 4.0))

meshes = [
    {"name": "TrailheadStage", "primitives": [
        primitive(stage_wood, 0),
        primitive(stage_slate, 1),
        primitive(stage_orange, 2),
        primitive(ground, 6),
    ]},
    {"name": "FoliageCard", "primitives": [primitive(quad(1.8, 2.25), 4)]},
    {"name": "TrailMapPanel", "primitives": [primitive(quad(1.92, 1.25), 5)]},
    {"name": "Bottle", "primitives": [
        primitive(cylinder(0.34, 1.34, 0), 2),
        primitive(merge(cylinder(0.27, 0.22, 0.78), cylinder(0.355, 0.11, 0.34)), 3),
    ]},
]

materials = [
    {"name": "TrailWood", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "baseColorFactor": [0.72, 0.48, 0.28, 1], "metallicFactor": 0, "roughnessFactor": 0.88}},
    {"name": "SlateMetal", "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}, "baseColorFactor": [0.16, 0.23, 0.28, 1], "metallicFactor": 0.72, "roughnessFactor": 0.28}},
    {"name": "SafetyOrange", "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}, "baseColorFactor": [0.95, 0.31, 0.07, 1], "metallicFactor": 0.35, "roughnessFactor": 0.34}},
    {"name": "DarkRubber", "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}, "baseColorFactor": [0.035, 0.045, 0.05, 1], "metallicFactor": 0, "roughnessFactor": 0.9}},
    {"name": "FoliageCutout", "alphaMode": "MASK", "alphaCutoff": 0.42, "doubleSided": True, "pbrMetallicRoughness": {"baseColorTexture": {"index": 2}, "baseColorFactor": [0.82, 0.9, 0.76, 1], "metallicFactor": 0, "roughnessFactor": 1}},
    {"name": "HolographicMap", "alphaMode": "BLEND", "doubleSided": True, "emissiveFactor": [0.03, 0.16, 0.20], "pbrMetallicRoughness": {"baseColorTexture": {"index": 3}, "baseColorFactor": [0.75, 1, 1, 0.64], "metallicFactor": 0, "roughnessFactor": 0.2}},
    {"name": "GroundStone", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "baseColorFactor": [0.34, 0.37, 0.34, 1], "metallicFactor": 0, "roughnessFactor": 0.95}},
]

gltf = {
    "asset": {"version": "2.0", "generator": "fusion backpack showcase generator"},
    "scene": 0,
    "scenes": [{"nodes": [0, 1, 2, 3, 4, 5]}],
    "nodes": [
        {"name": "TrailheadStage", "mesh": 0},
        {"name": "LeftFoliage", "mesh": 1, "translation": [-3.15, -0.42, 0.52], "scale": [0.72, 0.72, 0.72]},
        {"name": "RightFoliage", "mesh": 1, "translation": [3.55, -0.72, 0.30], "scale": [0.52, 0.52, 0.52]},
        {"name": "LeftFoliageSmall", "mesh": 1, "translation": [-3.70, -0.78, 0.36], "scale": [0.43, 0.43, 0.43]},
        {"name": "TrailMap", "mesh": 2, "translation": [3.00, 0.56, 0.16]},
        {"name": "Bottle", "mesh": 3, "translation": [-2.20, -0.83, 0.52], "rotation": [0, 0, -0.087156, 0.996195]},
    ],
    "meshes": meshes,
    "materials": materials,
    "textures": [{"source": index, "sampler": 0} for index in range(4)],
    "images": [
        {"uri": "../textures/brick_albedo.jpg"},
        {"uri": "../textures/showcase_white_albedo.png"},
        {"uri": "../textures/showcase_foliage_albedo.png"},
        {"uri": "../textures/showcase_trail_map_albedo.png"},
    ],
    "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
    "accessors": accessors,
    "bufferViews": buffer_views,
    "buffers": [{"uri": BIN_PATH.name, "byteLength": len(blob)}],
}

MESH_DIR.mkdir(parents=True, exist_ok=True)
BIN_PATH.write_bytes(blob)
GLTF_PATH.write_text(json.dumps(gltf, indent=2) + "\n")
print(f"wrote {GLTF_PATH.relative_to(ROOT)} and {BIN_PATH.relative_to(ROOT)} ({len(blob)} bytes)")
