class_name Toys
extends RefCounted
## 장난감 6종의 로우폴리 형태와 박스 모델. 기본 도형을 조합해 코드로 만든다.

## 같은 형태 장난감 몇 개가 박스 1개가 되는가
const BOX_SIZE := 4
const NAMES: Array[String] = ["곰 인형", "자동차", "블록", "공", "로봇", "오리"]
## 형태별 대표 색 (박스 라벨에도 쓴다)
const COLORS: Array[Color] = [
	Color(0.62, 0.42, 0.26),
	Color(0.9, 0.25, 0.25),
	Color(0.25, 0.5, 0.95),
	Color(0.3, 0.8, 0.4),
	Color(0.65, 0.5, 0.9),
	Color(0.98, 0.85, 0.2),
]
const CARDBOARD := Color(0.78, 0.6, 0.38)
const DARK := Color(0.15, 0.15, 0.17)
const WHITE := Color(0.95, 0.95, 0.95)

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


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
			_part(root, "ball", Vector3(0.07, 0.06, 0.06), Vector3(0, 0.26, 0.07), Color(0.85, 0.7, 0.55))
		1:  # 자동차
			_part(root, "box", Vector3(0.3, 0.08, 0.16), Vector3(0, 0.08, 0), main)
			_part(root, "box", Vector3(0.15, 0.08, 0.14), Vector3(-0.01, 0.16, 0), Color(0.7, 0.85, 0.95))
			for x: float in [-0.09, 0.09]:
				for z: float in [-0.085, 0.085]:
					_part(root, "cyl", Vector3(0.07, 0.03, 0.07), Vector3(x, 0.035, z), DARK, Vector3(PI / 2.0, 0, 0))
		2:  # 블록
			_part(root, "box", Vector3(0.26, 0.13, 0.16), Vector3(0, 0.065, 0), main)
			_part(root, "cyl", Vector3(0.07, 0.04, 0.07), Vector3(-0.065, 0.15, 0), main)
			_part(root, "cyl", Vector3(0.07, 0.04, 0.07), Vector3(0.065, 0.15, 0), main)
		3:  # 공
			_part(root, "ball", Vector3(0.26, 0.26, 0.26), Vector3(0, 0.13, 0), main)
			_part(root, "cyl", Vector3(0.265, 0.04, 0.265), Vector3(0, 0.13, 0), WHITE)
		4:  # 로봇
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
			_part(root, "box", Vector3(0.06, 0.03, 0.07), Vector3(0, 0.2, 0.16), Color(0.95, 0.5, 0.15))
	return root


## 형태 색 라벨이 붙은 골판지 박스. 가운데가 원점이다.
static func make_box(type: int, size: float) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.mesh = _mesh("box")
	box.material_override = _material(CARDBOARD)
	box.scale = Vector3.ONE * size
	var label := MeshInstance3D.new()
	label.mesh = _mesh("box")
	label.material_override = _material(COLORS[type])
	label.scale = Vector3(0.6, 0.6, 0.06)
	label.position = Vector3(0, 0, 0.5)
	box.add_child(label)
	return box


## 이미 만든 박스의 라벨을 다른 형태 색으로 바꾼다.
static func set_box_type(box: MeshInstance3D, type: int) -> void:
	(box.get_child(0) as MeshInstance3D).material_override = _material(COLORS[type])


static func _part(
	root: Node3D, mesh_key: String, size: Vector3, at: Vector3, color: Color,
	rotation: Vector3 = Vector3.ZERO
) -> void:
	var part := MeshInstance3D.new()
	part.mesh = _mesh(mesh_key)
	part.material_override = _material(color)
	part.scale = size
	part.position = at
	part.rotation = rotation
	root.add_child(part)


static func _mesh(key: String) -> Mesh:
	if _meshes.is_empty():
		var box := BoxMesh.new()
		var ball := SphereMesh.new()
		ball.radial_segments = 8
		ball.rings = 4
		var cyl := CylinderMesh.new()
		cyl.height = 1.0
		cyl.radial_segments = 8
		_meshes = {"box": box, "ball": ball, "cyl": cyl}
	return _meshes[key]


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_materials[color] = material
	return _materials[color]
