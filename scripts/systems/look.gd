class_name Look
extends RefCounted
## 화면 꾸밈 공통: 재질과 코드로 만든 무늬(격자·가로 줄·사선 줄).
## 무늬 재질은 로컬 트라이플래너라서 크기를 직접 준 메시(스케일 1)에 쓴다. 1 단위 = 1m.

const TEXTURE_SIZE := 64

static var _cache: Dictionary = {}


## 단색 재질
static func matte(color: Color, roughness: float = 0.7) -> StandardMaterial3D:
	var key := "matte %s %.2f" % [color, roughness]
	if not _cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		_cache[key] = material
	return _cache[key]


## 스스로 빛나는 재질 (전등, 로봇 눈)
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "glow %s %.2f" % [color, energy]
	if not _cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_cache[key] = material
	return _cache[key]


## 격자 줄이 있는 재질 (바닥 타일, 벽 패널). tile: 한 칸의 크기(m)
static func grid(color: Color, line: Color, tile: float) -> StandardMaterial3D:
	var key := "grid %s %s %.2f" % [color, line, tile]
	if not _cache.has(key):
		var image := _image(color)
		for i in TEXTURE_SIZE:
			for t in 2:
				image.set_pixel(i, t, line)
				image.set_pixel(t, i, line)
		_cache[key] = _textured(image, tile)
	return _cache[key]


## 가로 줄이 있는 재질 (셔터 문). 호출할 때마다 새 재질을 주므로 albedo_color로 색을 바꿀 수 있다.
static func bands(color: Color, line: Color, band: float) -> StandardMaterial3D:
	var image := _image(color)
	for x in TEXTURE_SIZE:
		for y in 6:
			image.set_pixel(x, y, line)
	return _textured(image, band)


## 노랑·검정 사선 줄 (안전 표시)
static func hazard(tile: float = 0.8) -> StandardMaterial3D:
	var key := "hazard %.2f" % tile
	if not _cache.has(key):
		var image := _image(Color(1.0, 0.8, 0.2))
		for x in TEXTURE_SIZE:
			for y in TEXTURE_SIZE:
				@warning_ignore("integer_division")
				if (x + y) / 16 % 2 == 1:
					image.set_pixel(x, y, Color(0.18, 0.18, 0.22))
		_cache[key] = _textured(image, tile)
	return _cache[key]


## 꼭짓점 색을 그대로 쓰는 재질. 여러 색의 상자를 하나의 메시로 합칠 때 쓴다.
static func vertex_color(roughness: float = 0.6) -> StandardMaterial3D:
	var key := "vertex %.2f" % roughness
	if not _cache.has(key):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = roughness
		_cache[key] = material
	return _cache[key]


## SurfaceTool에 한 가지 색의 직육면체(가운데 center, 크기 size)를 더한다. 평평한 면 법선.
static func add_cuboid(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var half := size / 2.0
	for axis in 3:
		for sign_value: float in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			var u := Vector3.ZERO
			u[u_axis] = half[u_axis]
			var v := Vector3.ZERO
			v[v_axis] = half[v_axis]
			var face := center + normal * half[axis]
			var quad: Array[Vector3] = [face - u - v, face + u - v, face + u + v, face - u + v]
			# Godot의 앞면은 시계 방향: 바깥에서 볼 때 반시계이면 순서를 뒤집는다
			var order: Array[int] = [0, 1, 2, 0, 2, 3]
			if (quad[1] - quad[0]).cross(quad[2] - quad[0]).dot(normal) > 0.0:
				order = [0, 2, 1, 0, 3, 2]
			for index in order:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(quad[index])


static func _image(color: Color) -> Image:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


static func _textured(image: Image, tile: float) -> StandardMaterial3D:
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE / tile
	material.roughness = 0.8
	return material
