extends Node
class_name BiliLiveApi

#--------------------全局设置部分（url、appid等设置）--------------------------
#api接口设置
const API_BASE_URL : String = "https://live-open.biliapi.com"
#项目id设置(需要修改成你自己的）
const app_id : int = 000000000000
#默认主播码设置
var code : String = ""
#项目key(需要修改成你自己的）
const key : String = "填写项目key"
#项目secret(需要修改成你自己的）
const secret : String = "填写项目secret"
#--------------------使用到的工具对象部分--------------------------
#网络请求工具
var _http_request = HTTPRequest.new()
#随机数生成工具
var rng = RandomNumberGenerator.new()
#签名加密对象
var crypto = Crypto.new()
#====================返回对象部分（用于项目启动及关闭）=============================
#主播信息
var anchor_info : biliLive_entity.AnchorInfo
#场次信息
var game_info : biliLive_entity.GameInfo
#长链信息
var websocket_info : biliLive_entity.WebsocketInfo
#定义一个枚举类型，表示API类别，用于分发信号
enum RequestType {
	START,
	END,
	HEART_BEAT,
}
# 网络请求。存储数据为请求 url 和请求类型
var _http_request_list: Array
var _http_request_type_list: Array[RequestType]
# 请求定时器，当定时器结束时出栈第一个网络请求
var _http_req_timer := Timer.new()
var _http_hear_beat_req_timer := Timer.new()
#====================信号定义部分=======================
signal on_api_start_finish(anchor_info: biliLive_entity.AnchorInfo, game_info: biliLive_entity.GameInfo,websocket_info: biliLive_entity.WebsocketInfo)
signal on_api_end_finish(response_body: Variant)
signal on_api_heart_beat_finish(response_body: Variant)
signal on_api_error(error_string: String)

func _ready():
	#初始化Http客户端收到回复的方法并挂在在当前节点之上
	_http_request.request_completed.connect(request_completed)
	add_child(_http_request)
	#初始化网络请求倒计时器并挂在到节点上
	_http_req_timer.wait_time = 2
	_http_req_timer.one_shot = true
	_http_req_timer.timeout.connect(
		func():
		#如果请求列表非空且请求间隔满足，开始下一个请求
			if not _http_request_list.is_empty() and _http_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				var req = _http_request_list.pop_front()
				_postToBilibiliUrl(req.api_url, req.param)
	)
	add_child(_http_req_timer)
	#初始化心跳请求倒计时器并挂在到节点上
	_http_hear_beat_req_timer.wait_time = 20
	_http_hear_beat_req_timer.one_shot = false
	_http_hear_beat_req_timer.stop()
	_http_hear_beat_req_timer.timeout.connect(
		func():
		#如果请求列表非空且请求间隔满足，开始下一个请求
			if not game_info == null:
				_heart_beat(game_info.game_id)
	)
	add_child(_http_hear_beat_req_timer)
#通用POST到Bilibili互动玩法API的工具(参考实现：https://open-live.bilibili.com/document/74eec767-e594-7ddd-6aba-257e8317c05d）
func _postToBilibiliUrl(api_url : String , param : String):
	var headerString = PackedStringArray()
	var timestamp = "%d" % [int(Time.get_unix_time_from_system())]
	var signatureNonce = rng.randi()
	headerString.append("x-bili-accesskeyid:%s" % [key])
	headerString.append("x-bili-content-md5:%s" % [param.md5_text()])
	headerString.append("x-bili-signature-method:HMAC-SHA256")
	headerString.append("x-bili-signature-nonce:%s" % [signatureNonce])
	headerString.append("x-bili-signature-version:1.0")
	headerString.append("x-bili-timestamp:%s" % [timestamp])
	var need_hmac_string = "\n".join(headerString)
	var signature = crypto.hmac_digest(HashingContext.HASH_SHA256,secret.to_utf8_buffer(),need_hmac_string.to_utf8_buffer()).hex_encode()
	headerString.append("Authorization:%s" % [signature])
	headerString.append("Content-Type:application/json")
	headerString.append("Accept:application/json")
	headerString.append("Referrer-Policy:no-referrer")


	var error = _http_request.request(API_BASE_URL+api_url,headerString,HTTPClient.METHOD_POST,param)
	if error != OK:
		push_error("【BILI_LIVE_API】在HTTP请求中发生了一个错误。")
	_http_req_timer.start()
#追加请求部分，统一处理追加请求URL、参数及类型。每次将新的请求加入队列，依次请求。
func _http_request_append(api_url : String , param : String):
	if _http_req_timer.is_stopped() and _http_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		if _http_request_list.is_empty():
			_postToBilibiliUrl(api_url, param)
		else:
			var req = _http_request_list.pop_front()
			_postToBilibiliUrl(req.api_url, req.param)
			_http_request_list.append({"api_url":api_url, "param":param})
	else:
		_http_request_list.append({"api_url":api_url, "param":param})
#分类进行API请求
func _start(_code : String , _app_id:int):
	_http_request_append("/v2/app/start",'{"code":"%s","app_id":%d}'%[_code,_app_id])
	_http_request_type_list.append(RequestType.START)
	_http_hear_beat_req_timer.start()
func _end(_game_id : String , _app_id:int):
	_http_request_append("/v2/app/end",'{"app_id":%d,"game_id":"%s"}'%[_app_id,_game_id])
	_http_request_type_list.append(RequestType.END)
	_http_hear_beat_req_timer.stop()
	pass
func _heart_beat(_game_id : String):
	_http_request_append("/v2/app/heartbeat", '{"game_id":"%s"}'%[_game_id])
	_http_request_type_list.append(RequestType.HEART_BEAT)	
#收到API回复后的处理
func request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	#弹出本次请求类型
	var request_type = _http_request_type_list.pop_front()
	if result != HTTPRequest.RESULT_SUCCESS:
		on_api_error.emit("网络请求出错，返回错误代码：%d" % [result])
		return
	if response_code != 200:
		on_api_error.emit("接口请求出错，返回错误代码：%d" % [response_code])
		return
	var response_body = JSON.parse_string(body.get_string_from_utf8())
	if response_body.code != 0 :
		on_api_error.emit("请求错误: {code} {message}".format(response_body))
	else :
		match request_type:
			RequestType.START:
				handle_start(response_body)
			RequestType.END:
				handle_end(response_body)
			RequestType.HEART_BEAT:
				handle_heart_beat(response_body)
func handle_start(response_body):
	anchor_info = biliLive_entity.AnchorInfo.new(
		response_body.data.anchor_info.room_id,
		response_body.data.anchor_info.uface,
		response_body.data.anchor_info.open_id,
		response_body.data.anchor_info.uname
	)
	game_info = biliLive_entity.GameInfo.new(
		response_body.data.game_info.game_id
	)
	websocket_info = biliLive_entity.WebsocketInfo.new(
		response_body.data.websocket_info.auth_body,
		PackedStringArray(response_body.data.websocket_info.wss_link)
	)
	on_api_start_finish.emit(anchor_info,game_info,websocket_info)
func handle_end(response_body):
	on_api_end_finish.emit(response_body)
func handle_heart_beat(response_body):
	on_api_heart_beat_finish.emit(response_body)
	
