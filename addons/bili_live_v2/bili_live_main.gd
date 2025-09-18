extends Node
class_name BiliLiveMain

@onready var pre_start_container=$ColorRect/MarginContainer/Background/PreStartContainer
@onready var code_input :TextEdit=$ColorRect/MarginContainer/Background/PreStartContainer/CodeContainer/TextureRect/CodeInput
@onready var code_input_clean_btn=$ColorRect/MarginContainer/Background/PreStartContainer/CodeContainer/TextureRect/CodeInputCleanBtn
@onready var to_get_code_btn=$ColorRect/MarginContainer/Background/PreStartContainer/GetCodeContainer/ColorRect/Button
@onready var start_btn=$ColorRect/MarginContainer/Background/PreStartContainer/StartGameContainer/StartBtn

@onready var running_container=$ColorRect/MarginContainer/Background/RunningContainer
@onready var damuk_scroll_container=$ColorRect/MarginContainer/Background/RunningContainer/DamukScrollContainer
@onready var damuk_container=$ColorRect/MarginContainer/Background/RunningContainer/DamukScrollContainer/DamukContainer
@onready var end_btn=$ColorRect/MarginContainer/Background/RunningContainer/CenterContainer/EndBtn

# websocket 客户端
var _client = BiliLiveWs.new()
# HTTP 请求 API
var _api = BiliLiveApi.new()
#自定义显示弹幕消息的条数
const DAMUK_ITEM_COUNT_MAX := 50

#========================触发信号处理部分========================
#各类收到消息后的结构体详见:https://open-live.bilibili.com/document/f9ce25be-312e-1f4a-85fd-fef21f1637f8
#获取弹幕信息
signal on_live_open_platform_dm(messages: Variant)
#获取礼物信息
signal on_live_open_platform_send_gift(messages: Variant)
#获取付费留言
signal on_live_open_platform_super_chat(messages: Variant)
#付费留言下线
signal on_live_open_platform_super_chat_del(messages: Variant)
#付费大航海
signal on_live_open_platform_guard(messages: Variant)
#点赞信息(请注意：对单一用户最近2秒聚合发送一次点赞次数)
signal on_live_open_platform_like(messages: Variant)

#项目启动时触发
signal on_start(anchor_info: biliLive_entity.AnchorInfo, game_info: biliLive_entity.GameInfo,websocket_info: biliLive_entity.WebsocketInfo)
#项目启动时发生错误时触发
signal on_start_error()
#项目结束时触发
signal on_end()
#api发生错误时通过该方法向外抛出
signal on_api_error(msg:String)

#正则表达式检测对象（检查身份码是否只含有英文与数字）
var reg_ex := RegEx.create_from_string("^[A-Z0-9]+$")
func _ready():
	running_container.visible=false
	#初始化按钮方法
	code_input_clean_btn.pressed.connect(_clean_code_input)
	to_get_code_btn.pressed.connect(_to_get_code)
	start_btn.pressed.connect(_to_start)
	end_btn.pressed.connect(_to_end)
	#挂载节点及信号连接
	add_child(_api)
	_api.connect("on_api_start_finish",on_api_start_finish)
	_api.connect("on_api_end_finish",on_api_end_finish)
	_api.connect("on_api_heart_beat_finish",on_api_heart_beat_finish)
	_api.connect("on_api_error",handle_api_error)
	add_child(_client)
	_client.connect("on_ws_received_message",on_ws_received_message)
	_client.connect("on_ws_connection_created",on_ws_connection_created)
	_client.connect("on_ws_connection_colsed",on_ws_connection_colsed)
	pass 
#准备使用身份码进行API连接的方法
func _to_start():
	var code = code_input.text
	code = code.to_upper()
	if not _validate_code(code):
		_toast("【错误】您提供的身份码不符合要求")
		on_start_error.emit()
		return
	_api._start(code,_api.app_id)
#准备使用身份码进行API关闭项目
func _to_end():
	_api._end(_api.game_info.game_id,_api.app_id)

#=======================API信号处理部分==================
func on_api_start_finish(anchor_info: biliLive_entity.AnchorInfo, game_info: biliLive_entity.GameInfo,websocket_info: biliLive_entity.WebsocketInfo):
	_toast("【API】项目已启动")
	start_btn.disabled = true
	pre_start_container.visible = false
	running_container.visible = true
	on_start.emit(anchor_info, game_info,websocket_info)
	_client._connect_websocket(_api.websocket_info)
	pass
func on_api_end_finish(response_body: Variant):
	_toast("【API】项目已结束")
	start_btn.disabled = false
	pre_start_container.visible = true
	running_container.visible = false
	on_end.emit()
	_client._disconnect_websocket()
	pass
func handle_api_error(error_string:String):
	start_btn.disabled = false
	_toast("【API】错误：%s" % error_string)
	on_api_error.emit(error_string)
	pass
func on_api_heart_beat_finish(response_body: Variant):
	pass
#======================WS信号处理部分======================
func on_ws_received_message(received_message:Variant):
	match received_message.cmd:
		"LIVE_OPEN_PLATFORM_DM":
			if received_message.data.dm_type == 0:
				_add_damuk_item("【弹幕-航海等级{guard_level}】{uname}:\n{msg}".format(received_message.data))
			else :
				_add_damuk_item("【弹幕-航海等级{guard_level}】{uname}:\n[表情包]{emoji_img_url}".format(received_message.data))				
			on_live_open_platform_dm.emit(received_message.data)
		"LIVE_OPEN_PLATFORM_SEND_GIFT":
			_add_damuk_item("【礼物-航海等级{guard_level}】{uname}:\n赠送了价值{price}的{gift_name}(ID：{gift_id})".format(received_message.data))
			on_live_open_platform_send_gift.emit(received_message.data)
		"LIVE_OPEN_PLATFORM_SUPER_CHAT":
			_add_damuk_item("【付费留言-航海等级{guard_level}】{uname}:\n支付{rmb}元，留言“{message}”".format(received_message.data))			
			on_live_open_platform_super_chat.emit(received_message.data)
		"LIVE_OPEN_PLATFORM_SUPER_CHAT_DEL":
			#作者不知道这是什么...谅解，或者联系我更新（QQ：910847746）
			on_live_open_platform_super_chat_del.emit(received_message.data)
		"LIVE_OPEN_PLATFORM_GUARD":
			_add_damuk_item("【大航海-{user_info.open_id}】{user_info.uname}:\n开通了大航海[等级-{guard_level} 时长-{guard_num}个月]".format(received_message.data))
			on_live_open_platform_guard.emit(received_message.data)
		"LIVE_OPEN_PLATFORM_LIKE":
			_add_damuk_item("【点赞】{uname}:点赞了{like_count}次".format(received_message.data))
			on_live_open_platform_like.emit(received_message.data)
	pass
func on_ws_connection_created(successful:bool,message:String):
	_toast("【WS】长连接已建立")
	pass
func on_ws_connection_colsed(code: int, reason: String):
	if not code == 1010:
		_toast("【WS】长连接关闭: code: %d, reason: %s" % [code, reason])
		push_error("【WS】长连接关闭: code: %d, reason: %s" % [code, reason])
		_client._reconnect_websocket()
	else :
		_toast("【WS】长连接已手动关闭")
	pass
#=========================工具类部分=======================
var _last_toast_time = 0
var _last_toast_y_offset : int = 0
#在登录框种显示Toast消息的方法
func _toast(str:String):
	var root = $"."
	var toast : Node= load("res://addons/bili_live_v2/bili_live_toast.tscn").instantiate()
	var now_time = Time.get_unix_time_from_system()
	if (now_time - _last_toast_time) < 3:
		_last_toast_y_offset = _last_toast_y_offset + 25
		_last_toast_time = now_time
	else :
		_last_toast_y_offset = 0
		_last_toast_time = now_time
	toast._set_position(Vector2(-toast.get_size().x/2,-root.get_size().y/2 + 10 + _last_toast_y_offset))
	toast.get_node("ToastLabel").text = str
	root.add_child(toast)
#检查主播码是否符合要求(符合要求 true）（不符合要求 false）
func _validate_code(code:String) -> bool:
	var result = reg_ex.search(code)
	if result:
		return true
	else :
		return false
#清空身份码输入框的方法
func _clean_code_input():
	code_input.text=""
	_toast("【提示】身份码已清空")
	pass
func _set_code(code:String):
	code_input.text=code
	pass
#跳转获取身份码链接的方法
func _to_get_code():
	_toast("【提示】查看网页右下角【身份码】")
	OS.shell_open("https://play-live.bilibili.com/")
func _add_damuk_item(str:String):
	var children = damuk_container.get_children()
	if children.size() >= DAMUK_ITEM_COUNT_MAX:
		children[0].queue_free()
	var damuk_item : Node= load("res://addons/bili_live_v2/damuk_item.tscn").instantiate()
	damuk_item.text = str
	damuk_container.add_child(damuk_item)
#在有新的弹幕时，滚动条自动滚动到末尾
func _on_damuk_container_resized():
	if damuk_container != null:
		damuk_scroll_container.scroll_vertical = damuk_container.size.y + 40
	pass 
