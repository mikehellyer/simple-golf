extends SceneTree
## One-off tool: renders icon.svg to every size and format the installers
## need (PNGs, Windows .ico, macOS .icns) in packaging/icons/. Not part of the
## game; re-run by hand if the icon changes:
##   godot --headless --script res://tools/generate_icons.gd

const OUT := "res://packaging/icons"
const PNG_SIZES := [16, 32, 48, 64, 128, 256, 512, 1024]
const ICO_SIZES := [16, 32, 48, 64, 128, 256]
## ICNS chunk types that hold PNG data, by pixel size.
const ICNS_TYPES := {16: "icp4", 32: "icp5", 64: "icp6", 128: "ic07", 256: "ic08", 512: "ic09", 1024: "ic10"}


func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var pngs := {}
	for size in PNG_SIZES:
		var img := Image.new()
		img.load_svg_from_string(svg, size / 128.0)
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pngs[size] = img.save_png_to_buffer()
		img.save_png("%s/icon_%d.png" % [OUT, size])
	_write("%s/icon.ico" % OUT, _ico(pngs))
	_write("%s/icon.icns" % OUT, _icns(pngs))
	print("wrote icons to ", ProjectSettings.globalize_path(OUT))
	quit()


func _ico(pngs: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6)
	out.encode_u16(0, 0)
	out.encode_u16(2, 1)
	out.encode_u16(4, ICO_SIZES.size())
	var offset := 6 + 16 * ICO_SIZES.size()
	var data := PackedByteArray()
	for size in ICO_SIZES:
		var png: PackedByteArray = pngs[size]
		var entry := PackedByteArray()
		entry.resize(16)
		entry.encode_u8(0, size % 256)
		entry.encode_u8(1, size % 256)
		entry.encode_u16(4, 1)
		entry.encode_u16(6, 32)
		entry.encode_u32(8, png.size())
		entry.encode_u32(12, offset + data.size())
		out.append_array(entry)
		data.append_array(png)
	out.append_array(data)
	return out


func _icns(pngs: Dictionary) -> PackedByteArray:
	var body := PackedByteArray()
	for size in ICNS_TYPES:
		var png: PackedByteArray = pngs[size]
		body.append_array(ICNS_TYPES[size].to_ascii_buffer())
		body.append_array(_be32(png.size() + 8))
		body.append_array(png)
	var out := "icns".to_ascii_buffer()
	out.append_array(_be32(body.size() + 8))
	out.append_array(body)
	return out


static func _be32(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255])


static func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
