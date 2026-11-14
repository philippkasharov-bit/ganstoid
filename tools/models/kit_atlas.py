"""K3: bake the house kit's texture sheet in Blender (Cycles, CPU).

Each material slot of kit_lib gets a 512 px cell of a 2048 px sheet (a
4 x 4 grid), baked from a procedural Blender material. The alpha channel is
the paint mask: 1 where the game multiplies the cell by the house's own
colour (trim, door, garage), 0 where the baked colour is final.

    python3 tools/models/kit_atlas.py art/textures/kit_atlas.png
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import kit_lib as kit  # noqa: E402

CELL = 512
GRID = 4
TINTED = {"paint", "door", "garage"}


def _nodes(mat: bpy.types.Material) -> tuple[bpy.types.NodeTree, bpy.types.Node]:
    """A material whose surface is pure emission (baked as is); returns its tree and the emission node."""
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    emit = tree.nodes.new("ShaderNodeEmission")
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(emit.outputs[0], out.inputs[0])
    return tree, emit


def _ramp(tree: bpy.types.NodeTree, source: bpy.types.NodeSocket, low: tuple, high: tuple) -> bpy.types.NodeSocket:
    ramp = tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*low, 1.0)
    ramp.color_ramp.elements[1].color = (*high, 1.0)
    tree.links.new(source, ramp.inputs[0])
    return ramp.outputs[0]


def _noise(tree: bpy.types.NodeTree, scale: float, detail: float = 6.0) -> bpy.types.NodeSocket:
    noise = tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    return noise.outputs["Fac"]


def _wave(tree: bpy.types.NodeTree, scale: float, distortion: float, bands: str = "BANDS") -> bpy.types.NodeSocket:
    wave = tree.nodes.new("ShaderNodeTexWave")
    wave.wave_type = bands
    wave.inputs["Scale"].default_value = scale
    wave.inputs["Distortion"].default_value = distortion
    return wave.outputs["Fac"]


def recipe(slot: str) -> bpy.types.Material:
    """The procedural look of one slot (tinted slots are grey: the game colours them)."""
    mat = bpy.data.materials.new("bake_" + slot)
    tree, emit = _nodes(mat)
    looks = {
        "paint": lambda: _ramp(tree, _noise(tree, 40.0), (0.8, 0.8, 0.8), (0.9, 0.9, 0.9)),
        "door": lambda: _ramp(tree, _wave(tree, 6.0, 6.0), (0.74, 0.74, 0.74), (0.9, 0.9, 0.9)),
        "glass": lambda: _ramp(tree, _wave(tree, 0.6, 0.5), (0.12, 0.17, 0.24), (0.42, 0.52, 0.62)),
        "frosted": lambda: _ramp(tree, _noise(tree, 60.0), (0.62, 0.68, 0.7), (0.8, 0.84, 0.86)),
        "garage": lambda: _ramp(tree, _wave(tree, 18.0, 0.2), (0.72, 0.72, 0.72), (0.92, 0.92, 0.92)),
        "concrete": lambda: _ramp(tree, _noise(tree, 30.0, 10.0), (0.52, 0.5, 0.47), (0.74, 0.72, 0.68)),
        "roof_tile": lambda: _ramp(tree, _wave(tree, 9.0, 1.2), (0.42, 0.17, 0.1), (0.78, 0.38, 0.24)),
        "metal": lambda: _ramp(tree, _wave(tree, 2.0, 12.0), (0.22, 0.23, 0.24), (0.42, 0.43, 0.45)),
        "brick": lambda: _brick(tree),
        "rafter": lambda: _ramp(tree, _wave(tree, 4.0, 9.0), (0.32, 0.2, 0.12), (0.55, 0.38, 0.24)),
        "ac": lambda: _ramp(tree, _noise(tree, 25.0), (0.66, 0.67, 0.68), (0.84, 0.85, 0.86)),
    }
    tree.links.new(looks[slot](), emit.inputs["Color"])
    return mat


def _brick(tree: bpy.types.NodeTree) -> bpy.types.NodeSocket:
    brick = tree.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 6.0
    brick.inputs["Color1"].default_value = (0.42, 0.14, 0.09, 1.0)
    brick.inputs["Color2"].default_value = (0.55, 0.22, 0.14, 1.0)
    brick.inputs["Mortar"].default_value = (0.62, 0.6, 0.55, 1.0)
    return brick.outputs["Color"]


def bake(slot: str) -> np.ndarray:
    """One slot baked onto a unit plane: CELL x CELL RGB in 0..1."""
    kit.reset()
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    plane = bpy.context.active_object
    plane.data.materials.append(recipe(slot))
    image = bpy.data.images.new("cell_" + slot, CELL, CELL)
    node = plane.active_material.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    plane.active_material.node_tree.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    bpy.ops.object.bake(type="EMIT")
    return np.array(image.pixels[:]).reshape(CELL, CELL, 4)[::-1, :, :3]


def main(out: str) -> None:
    sheet = np.zeros((CELL * GRID, CELL * GRID, 4))
    for k, slot in enumerate(kit.SLOTS):
        row, col = divmod(k, GRID)
        rgb = bake(slot)   # the image is sRGB already: its pixels are what the file stores
        sheet[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL, :3] = rgb
        sheet[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL, 3] = 1.0 if slot in TINTED else 0.0
        print("baked", slot)
    Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8), "RGBA").save(out)
    print("sheet", out)


if __name__ == "__main__":
    main(sys.argv[-1])
