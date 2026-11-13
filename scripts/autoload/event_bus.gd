extends Node
## 전역 시그널 허브. 시스템 간 직접 참조를 줄인다.

signal toy_sorted(total_sorted: int)
signal coins_changed(coins: int)
signal warehouse_unlocked(warehouse_id: int)
signal shelf_completed(warehouse_id: int, floor_index: int, shelf_index: int)
## 조준 중인 대상에 대한 안내 문구 (없으면 빈 문자열)
signal aim_text_changed(text: String)
## 잠깐 띄우는 알림
signal message_shown(text: String)
