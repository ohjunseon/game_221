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
	# 윗면과 옆면을 두르는 테이프 (라벨이 첫 번째 자식이어야 한다: set_box_type 참고)
	var tape := MeshInstance3D.new()
	tape.mesh = _mesh("box")
	tape.material_override = _material(TAPE)
	tape.scale = Vector3(0.2, 1.02, 1.02)
	box.add_child(tape)
	return box


## 이미 만든 박스의 라벨을 다른 형태 색으로 바꾼다.
static func set_box_type(box: MeshInstance3D, type: int) -> void:
	(box.get_child(0) as MeshInstance3D).material_override = _material(COLORS[type])


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
