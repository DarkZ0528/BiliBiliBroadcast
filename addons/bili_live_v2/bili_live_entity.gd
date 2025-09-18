extends RefCounted
class_name biliLive_entity
#主播信息类
class AnchorInfo extends RefCounted:
	var room_id : int :
		set(_room_id):
			room_id = _room_id
		get:
			return room_id
	var uface : String :
		set(_uface):
			uface = _uface
		get:
			return uface
	var open_id : String :
		set(_open_id):
			open_id = _open_id
		get:
			return open_id
	var uname : String :
		set(_uname):
			uname = _uname
		get:
			return uname
			
	func _init(_room_id:int,_uface:String,_open_id:String,_uname:String) -> void:
		self.room_id = _room_id
		self.uface = _uface
		self.open_id = _open_id
		self.uname = _uname
	func _to_string() -> String:
		return "room_id:%d,uface:%s,open_id:%s,uname:%s" % [room_id,uface,open_id,uname]
#场次信息类
class GameInfo extends RefCounted:
	var game_id : String :
		set(_game_id):
			game_id = _game_id
		get:
			return game_id
	func _init(game_id:String,) -> void:
		self.game_id = game_id
	func _to_string() -> String:
		return "game_id:%s" % [game_id]
#长连信息类
class WebsocketInfo extends RefCounted:
	var auth_body : String :
		set(_auth_body):
			auth_body = _auth_body
		get:
			return auth_body
	var wss_link : PackedStringArray :
		set(_wss_link):
			wss_link = _wss_link
		get:
			return wss_link
	func _init(auth_body:String,wss_link:PackedStringArray) -> void:
		self.auth_body = auth_body
		self.wss_link = wss_link
	func _to_string() -> String:
		return "auth_body:%s,wss_link:%s" % [auth_body,wss_link]
