## TX1: what each city surface is made of. A surface's vertex colour carries
## its material in the alpha channel (SurfaceDetail.mark): stucco, brick,
## asphalt, grass... The Cutaway shader then lays a world-mapped detail
## texture over the flat colour (grain, joints, blades), so the palette and
## variety of R3D2 stay and the city stops looking like plastic. Textures are
## greyscale detail maps (mean grey = no change) in art/textures/<name>.png,
## made by tools/textures/prepare.py; a missing one is flat grey, so the
## surface just keeps its plain colour.
class_name SurfaceDetail
extends RefCounted

enum { STUCCO, BRICK, BLOCK, CLAY, SHINGLE, GRAVEL, ASPHALT, SIDEWALK, GRASS, DIRT, WOOD, TILE, CARPET }
const NONE := 15   # alpha 1.0: a plain colour
const NAMES := ["stucco", "brick", "block", "clay", "shingle", "gravel", "asphalt", "sidewalk", "grass", "dirt", "wood", "tile", "carpet"]
const TILE_M := [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 3.0, 2.0, 3.0, 2.0, 3.2, 2.0]   # metres one texture covers
const STRENGTH := [0.55, 0.8, 0.7, 0.8, 0.7, 0.45, 0.5, 0.5, 0.45, 0.6, 0.8, 0.7, 0.5]   # how much of the texture shows
const DIR := "res://art/textures/"
const SIZE := 512
const SLOTS := 15   # the shader's arrays (ids 0..14; 15 is NONE)

static var _array: Texture2DArray

## Colour `col` marked as material `id` (one of the enum, or NONE).
static func mark(col: Color, id: int) -> Color:
	return Color(col, float(id) / 15.0)

## Every detail map as one array texture (built once).
static func textures() -> Texture2DArray:
	if _array == null:
		var images: Array[Image] = []
		for name in NAMES:
			images.append(_load(name))
		_array = Texture2DArray.new()
		_array.create_from_images(images)
	return _array

## One map as SIZE x SIZE greyscale with mipmaps; flat grey when it is missing.
static func _load(name: String) -> Image:
	var path: String = DIR + name + ".png"
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		img = Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
		img.fill(Color(0.5, 0.5, 0.5))
	img.convert(Image.FORMAT_L8)
	if img.get_width() != SIZE or img.get_height() != SIZE:
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img
