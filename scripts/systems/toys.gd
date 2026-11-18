class_name Toys
extends RefCounted
## 장난감 6종의 로우폴리 형태와 박스 모델. 기본 도형을 조합해 코드로 만든다.

## 같은 형태 장난감 몇 개가 박스 1개가 되는가
const BOX_SIZE := 4
const NAMES: Array[String] = ["곰 인형", "자동차", "블록", "공", "로봇", "오리"]
## 형태별 대표 색 (박스 라벨에도 쓴다)
const COLORS: Array[Color] = [
	Color(0.8, 0.55, 0.34),
	Color(0.98, 0.38, 0.38),
	Color(0.32, 0.62, 1.0),
	Color(0.38, 0.86, 0.52),
	Color(0.7, 0.58, 0.98),
	Color(1.0, 0.85, 0.26),
]
const CARDBOARD := Color(0.86, 0.68, 0.45)
const DARK := Color(0.16, 0.16, 0.2)
const TAPE := Color(0.95, 0.85, 0.62)
const WHITE := Color(0.95, 0.95, 0.95)
const GOLD := Color(1.0, 0.8, 0.2)

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _box_meshes: Dictionary = {}
static var _field_meshes: Dictionary = {}
static var _far_mesh: BoxMesh
static var _gold_mesh: BoxMesh


static func count() -> int:
	return NAMES.size()


static func random_type() -> int:
	return randi() % NAMES.size()


## 바닥(y=0)에 놓인 장난감 모양. 높이 약 0.3m
static func make_visual(type: int) -> Node3D:
	var root := Node3D.new()
	var main := COLORS[type]
	match type:
		0:  # 곰 인형
			_part(root, "ball", Vector3(0.2, 0.22, 0.18), Vector3(0, 0.11, 0), main)
			_part(root, "ball", Vector3(0.15, 0.15, 0.15), Vector3(0, 0.27, 0), main)
			_part(root, "ball", Vector3(0.06, 0.06, 0.06), Vector3(-0.06, 0.35, 0), main)
			_part(root, "ball", Vector3(0.06, 0.06, 0.06), Vector3(0.06, 0.35, 0), main)
			var cream := Color(0.97, 0.86, 0.68)
			_part(root, "ball", Vector3(0.08, 0.06, 0.06), Vector3(0, 0.255, 0.065), cream)
			_part(root, "ball", Vector3(0.13, 0.14, 0.06), Vector3(0, 0.11, 0.07), cream)
			_part(root, "ball", Vector3(0.03, 0.025, 0.02), Vector3(0, 0.268, 0.095), DARK)
			for x: float in [-1.0, 1.0]:
				_part(root, "ball", Vector3(0.025, 0.03, 0.02), Vector3(0.035 * x, 0.295, 0.066), DARK)
				_part(root, "ball", Vector3(0.07, 0.09, 0.07), Vector3(0.105 * x, 0.15, 0.02), main)
				_part(root, "ball", Vector3(0.08, 0.06, 0.09), Vector3(0.06 * x, 0.03, 0.06), main)
		1:  # 자동차
			_part(root, "box", Vector3(0.3, 0.08, 0.16), Vector3(0, 0.08, 0), main)
			_part(root, "box", Vector3(0.15, 0.08, 0.14), Vector3(-0.01, 0.16, 0), Color(0.75, 0.9, 1.0))
			_part(root, "box", Vector3(0.16, 0.015, 0.15), Vector3(-0.01, 0.205, 0), main)
			_part(root, "box", Vector3(0.302, 0.02, 0.05), Vector3(0, 0.111, 0), WHITE)
			for z: float in [-0.05, 0.05]:
				_part(root, "box", Vector3(0.012, 0.03, 0.04), Vector3(0.15, 0.09, z), Color(1.0, 0.92, 0.5))
			for x: float in [-0.09, 0.09]:
				for z: float in [-0.085, 0.085]:
					_part(root, "cyl", Vector3(0.075, 0.03, 0.075), Vector3(x, 0.0375, z), DARK, Vector3(PI / 2.0, 0, 0))
					_part(root, "cyl", Vector3(0.035, 0.034, 0.035), Vector3(x, 0.0375, z), WHITE, Vector3(PI / 2.0, 0, 0))
		2:  # 블록
			_part(root, "box", Vector3(0.26, 0.13, 0.16), Vector3(0, 0.065, 0), main)
			for x: float in [-0.065, 0.065]:
				for z: float in [-0.04, 0.04]:
					_part(root, "cyl", Vector3(0.06, 0.04, 0.06), Vector3(x, 0.15, z), main.lightened(0.15))
		3:  # 공
			_part(root, "ball", Vector3(0.26, 0.26, 0.26), Vector3(0, 0.13, 0), main)
			_part(root, "cyl", Vector3(0.265, 0.04, 0.265), Vector3(0, 0.13, 0), WHITE)
			_part(root, "cyl", Vector3(0.265, 0.04, 0.265), Vector3(0, 0.13, 0), Color(1.0, 0.85, 0.26), Vector3(0, 0, PI / 2.0))
		4:  # 로봇
			for x: float in [-0.028, 0.028]:
				_part(root, "box", Vector3(0.028, 0.028, 0.01), Vector3(x, 0.28, 0.046), Color(0.4, 1.0, 1.0), Vector3.ZERO, true)
			_part(root, "box", Vector3(0.05, 0.008, 0.01), Vector3(0, 0.245, 0.046), DARK)
			_part(root, "box", Vector3(0.05, 0.04, 0.01), Vector3(0, 0.16, 0.051), Color(1.0, 0.85, 0.26))
			_part(root, "box", Vector3(0.16, 0.15, 0.1), Vector3(0, 0.145, 0), main)
			_part(root, "box", Vector3(0.11, 0.09, 0.09), Vector3(0, 0.27, 0), Color(0.8, 0.8, 0.85))
			_part(root, "box", Vector3(0.05, 0.07, 0.06), Vector3(-0.045, 0.035, 0), DARK)
			_part(root, "box", Vector3(0.05, 0.07, 0.06), Vector3(0.045, 0.035, 0), DARK)
			_part(root, "box", Vector3(0.04, 0.13, 0.05), Vector3(-0.105, 0.15, 0), Color(0.8, 0.8, 0.85))
			_part(root, "box", Vector3(0.04, 0.13, 0.05), Vector3(0.105, 0.15, 0), Color(0.8, 0.8, 0.85))
			_part(root, "cyl", Vector3(0.02, 0.05, 0.02), Vector3(0, 0.34, 0), Color(0.9, 0.3, 0.3))
		_:  # 오리
			_part(root, "ball", Vector3(0.2, 0.16, 0.26), Vector3(0, 0.08, 0), main)
			_part(root, "ball", Vector3(0.13, 0.13, 0.13), Vector3(0, 0.21, 0.08), main)
			_part(root, "box", Vector3(0.06, 0.03, 0.07), Vector3(0, 0.2, 0.16), Color(1.0, 0.55, 0.2))
			_part(root, "ball", Vector3(0.07, 0.07, 0.09), Vector3(0, 0.13, -0.13), main)
			for x: float in [-1.0, 1.0]:
				_part(root, "ball", Vector3(0.022, 0.026, 0.02), Vector3(0.04 * x, 0.235, 0.125), DARK)
				_part(root, "ball", Vector3(0.04, 0.09, 0.15), Vector3(0.1 * x, 0.09, -0.01), main.darkened(0.12))
	return root


## 형태 색 라벨이 붙은 골판지 박스. 가운데가 원점이다.
## 박스 몸통 색: 장난감 형태 색을 그대로 입혀 멀리서도 종류를 알아보게 한다
static func box_color(type: int) -> Color:
	return COLORS[type]


## 박스 앞면 라벨 색: 몸통보다 어둡게 해서 무늬로 보이게 한다
static func label_color(type: int) -> Color:
	return COLORS[type].darkened(0.4)


## 손에 들거나 바닥에 놓는 박스: 형태 색 몸통, 앞면 라벨, 테이프, 윗면에 그 장난감 모형.
## 자식 순서(라벨, 테이프, 모형)는 set_box_type이 기대한다.
static func make_box(type: int, size: float) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.mesh = _mesh("box")
	box.scale = Vector3.ONE * size
	var label := MeshInstance3D.new()
	label.mesh = _mesh("box")
	label.scale = Vector3(0.6, 0.6, 0.06)
	label.position = Vector3(0, 0, 0.5)
	box.add_child(label)
	var tape := MeshInstance3D.new()
	tape.mesh = _mesh("box")
	tape.material_override = _material(TAPE)
	tape.scale = Vector3(0.2, 1.02, 1.02)
	box.add_child(tape)
	var figure := MeshInstance3D.new()
	figure.scale = Vector3.ONE * 1.8
	figure.position = Vector3(0, 0.5, 0)
	box.add_child(figure)
	set_box_type(box, type)
	return box


## 선반에 쌓는 박스 메시: 골판지 몸통, 형태 색 라벨, 테이프를 하나로 합친 것 (크기 1, 형태별로 하나씩 공유)
static func box_mesh(type: int) -> ArrayMesh:
	if not _box_meshes.has(type):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Look.add_cuboid(st, Vector3.ZERO, Vector3.ONE, box_color(type))
		Look.add_cuboid(st, Vector3(0.0, 0.0, 0.5), Vector3(0.6, 0.6, 0.06), label_color(type))
		Look.add_cuboid(st, Vector3.ZERO, Vector3(0.2, 1.02, 1.02), TAPE)
		var mesh := st.commit()
		mesh.surface_set_material(0, Look.vertex_color(0.5))
		_box_meshes[type] = mesh
	return _box_meshes[type]


## 바닥에 깔린 장난감(ToyField)용: 형태의 부품을 낮은 면 수로 한 메시에 합친 것 (꼭짓점 색).
static func field_mesh(type: int) -> ArrayMesh:
	if _field_meshes.has(type):
		return _field_meshes[type]
	var low := {
		"box": BoxMesh.new(),
		"ball": SphereMesh.new(),
		"cyl": CylinderMesh.new(),
	}
	(low["ball"] as SphereMesh).radial_segments = 8
	(low["ball"] as SphereMesh).rings = 4
	(low["cyl"] as CylinderMesh).radial_segments = 8
	(low["cyl"] as CylinderMesh).height = 1.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var visual := make_visual(type)
	for part in visual.get_children():
		var instance := part as MeshInstance3D
		if instance == null:
			continue
		var key := "box"
		for mesh_name: String in _meshes:
			if _meshes[mesh_name] == instance.mesh:
				key = mesh_name
		var arrays: Array = (low[key] as Mesh).surface_get_arrays(0)
		var base := vertices.size()
		var xform := instance.transform
		var color := COLORS[type]
		var material := instance.material_override as StandardMaterial3D
		if material != null:
			color = material.albedo_color
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			vertices.append(xform * v)
			colors.append(color)
		for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			normals.append((xform.basis.inverse().transposed() * n).normalized())
		for i: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + i)
	visual.free()
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, Look.vertex_color(0.5))
	_field_meshes[type] = mesh
	return mesh


## 멀리 있는 바닥 장난감용 작은 육면체. 색은 MultiMesh 인스턴스 색으로 준다.
static func far_mesh() -> BoxMesh:
	if _far_mesh == null:
		_far_mesh = BoxMesh.new()
		_far_mesh.size = Vector3(0.24, 0.22, 0.24)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.6
		_far_mesh.material = material
	return _far_mesh


## 바닥의 황금 장난감: 빛나는 육면체 (집으면 진짜 황금 장난감이 된다)
static func gold_mesh() -> BoxMesh:
	if _gold_mesh == null:
		_gold_mesh = BoxMesh.new()
		_gold_mesh.size = Vector3(0.24, 0.24, 0.24)
		_gold_mesh.material = Look.glow(GOLD, 1.2)
	return _gold_mesh


## 이미 만든 박스의 라벨을 다른 형태 색으로 바꾼다.
static func set_box_type(box: MeshInstance3D, type: int) -> void:
	box.set_meta("box_type", type)
	(box.get_child(0) as MeshInstance3D).material_override = _material(label_color(type))
	(box.get_child(2) as MeshInstance3D).mesh = field_mesh(type)
	set_box_golden(box, box.get_meta("golden", false))


## 장난감(자식 메시 전부)을 금색으로 빛나게 한다.
static func gild(node: Node) -> void:
	for child in node.get_children():
		gild(child)
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = Look.glow(GOLD, 0.9)


## 박스 몸통을 금색 또는 형태 색으로 바꾼다. 라벨·테이프·모형은 그대로다.
static func set_box_golden(box: MeshInstance3D, golden: bool) -> void:
	box.set_meta("golden", golden)
	var type: int = box.get_meta("box_type", 0)
	box.material_override = Look.glow(GOLD, 0.9) if golden else _material(box_color(type))


static func _part(
	root: Node3D, mesh_key: String, size: Vector3, at: Vector3, color: Color,
	rotation: Vector3 = Vector3.ZERO, glowing: bool = false
) -> void:
	var part := MeshInstance3D.new()
	part.mesh = _mesh(mesh_key)
	part.material_override = Look.glow(color) if glowing else _material(color)
	part.scale = size
	part.position = at
	part.rotation = rotation
	root.add_child(part)


static func _mesh(key: String) -> Mesh:
	if _meshes.is_empty():
		var box := BoxMesh.new()
		var ball := SphereMesh.new()
		ball.radial_segments = 12
		ball.rings = 6
		var cyl := CylinderMesh.new()
		cyl.height = 1.0
		cyl.radial_segments = 12
		_meshes = {"box": box, "ball": ball, "cyl": cyl}
	return _meshes[key]


static func _material(color: Color) -> StandardMaterial3D:
	return Look.matte(color, 0.5)
