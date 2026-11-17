extends Node
## 전역 시그널 허브. 시스템 간 직접 참조를 줄인다.

signal toy_sorted(total_sorted: int)
signal coins_changed(coins: int)
signal warehouse_unlocked(warehouse_id: int)
signal shelf_completed(warehouse_id: int, floor_index: int, shelf_index: int)
## 선반 저장량이 바뀜 (key = "창고_층_선반")
signal shelf_changed(key: String)
signal skills_changed
signal skill_activated(id: String)
signal quest_changed
signal door_toggled(warehouse_id: int, is_open: bool)
## 조준 중인 대상에 대한 안내 문구 (없으면 빈 문자열)
signal aim_text_changed(text: String)
## 잠깐 띄우는 알림
signal message_shown(text: String)
## 화면 가운데에서 떠오르는 숫자·문구
signal popup_requested(text: String)
signal shake_requested(strength: float)
signal carried_changed(carried: int, capacity: int)
signal game_completed
## 엔딩: 곰 반장 칭찬 카드가 끝나면 하늘에서 거대 상자가 떨어진다
signal ending_box_requested
## 엔딩: 거대 상자가 땅에 닿음 (이어서 잠에서 깨는 카드)
signal ending_box_landed
