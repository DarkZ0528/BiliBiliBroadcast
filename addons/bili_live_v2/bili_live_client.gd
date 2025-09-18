extends Node
class_name BiliLiveWs
#V2API开启项目后的长连接处理类
#详见：https://open-live.bilibili.com/document/657d8e34-f926-a133-16c0-300c1afc6e6b
#==============================分割线================================

#Godot的Websocket连接对象
var _ws := WebSocketPeer.new()
#心跳包发送倒计时器
var _ws_hb_timer := Timer.new()
#自定义互动玩法长连接可用操作类型
enum OperationType {
	OP_HEARTBEAT = 2,  # 客户端发送的心跳包(30秒发送一次)
	OP_HEARTBEAT_REPLY = 3,  # 服务器收到心跳包的回复
	OP_SEND_SMS_REPLY = 5,  # 服务器推送的弹幕消息包
	OP_AUTH = 7,  # 客户端发送的鉴权包(客户端发送的第一个包)
	OP_AUTH_REPLY = 8  # 服务器收到鉴权包后的回复
}

enum ProtocolVersion {
	V0 = 0,  # JSON 格式的文本消息
	V2 = 2,  # zlib 压缩的数据包
}
#定义发包header长度，固定为16
const PACKET_HEADER_SIZE : int = 16
#定义心跳包heartbeat发送间隔，固定为30秒
const HEART_BEAT_INTERVAL : int = 30
#自定义一个重连次数
const reconnect_time : int = 1 
#自定义连接状态，用于判断是否第一次进行长连接及当前链接状态传递【未连接: false】【已连接: true】
var _ws_connected := false
#自定义处理链接状态【处理连接：true】【不处理链接：false】
var _ws_process := false
#鉴权包及长连接内容，应在API开启V2项目后的返回值中获取，在开始进行长连时，保存到当前
var _websocket_info :biliLive_entity.WebsocketInfo
#========================触发信号处理部分========================
signal on_ws_received_message(received_message:Variant)
signal on_ws_connection_created(successful:bool,message:String)
#长连接断开错误信号(服务段或客户端断开以及未连接成功均会触发）
signal on_ws_connection_colsed(code: int, reason: String)

func _ready():
	#初始化自定义连接状态及消息处理状态
	_ws_connected = false
	_ws_process = false
	#初始化心跳计时器，并指定倒计时结束时发送下一个心跳包，但此时不启动，收到鉴权包回复后再启动
	add_child(_ws_hb_timer)
	_ws_hb_timer.wait_time = HEART_BEAT_INTERVAL
	_ws_hb_timer.one_shot = false
	_ws_hb_timer.stop()
	_ws_hb_timer.timeout.connect(_send_heart_beat)
	
func _process(delta):
	if _ws_process:
		_ws.poll()
		var state = _ws.get_ready_state()
		match state:
			WebSocketPeer.STATE_CONNECTING:
				pass
			WebSocketPeer.STATE_OPEN:
				if not _ws_connected:
					_ws_connected = true
					#第一次打开长连，发送鉴权消息
					self._send_auth(_websocket_info.auth_body)
					#启动心跳计时器
					_ws_hb_timer.start()
				while _ws.get_available_packet_count():
					_process_packet(_ws.get_packet())
			WebSocketPeer.STATE_CLOSING:
				pass
			WebSocketPeer.STATE_CLOSED:
				_ws_connected = false
				_ws_process = false
				if not _ws_hb_timer.is_stopped():
					_ws_hb_timer.stop()
				var code = _ws.get_close_code()
				var reason = _ws.get_close_reason()
				on_ws_connection_colsed.emit(code, reason)
#用于启动长链接的方法
func _connect_websocket(_websocket_info :biliLive_entity.WebsocketInfo):
	self._websocket_info = _websocket_info
	for i in range(0,_websocket_info.wss_link.size()):
		var err = _ws.connect_to_url(_websocket_info.wss_link[i])
		if err != OK:
			_ws_process = false
		else :
			_ws_process = true
			on_ws_connection_created.emit(true,"【BILI_LIVE_WS】长连接创建成功")
			break
	if _ws_process == false:
		on_ws_connection_created.emit(true,"【BILI_LIVE_WS】长连接创建失败")
	pass
func _disconnect_websocket():
	if  _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close(1010)
	pass
func _reconnect_websocket():
	_connect_websocket(self._websocket_info)
	pass
#收到数据包的处理部分
func _process_packet(packet: PackedByteArray):
	var protcol_ver := _read_int_from_buf(packet, 6, 2)
	var operation_type := _read_int_from_buf(packet, 8, 4)
	var messages: PackedStringArray
	#判断版本协议是V0还是V2，分别解出数据存在messages中
	if protcol_ver == ProtocolVersion.V0:
		messages.append(packet.slice(16).get_string_from_utf8())
	elif protcol_ver == ProtocolVersion.V2:
		#zlib 压缩的 JSON 数据，则解压后返回包内内容
		messages.append_array(_decode_packet(packet))
	else:
		push_error("【BILI_LIVE_WS】收到未知的响应版本")
	if not messages.is_empty():
	#判断接收的数据包是那种类型，分别进行处理
		match operation_type :
			#收到心跳包回复，不进行处理
			OperationType.OP_AUTH_REPLY:
				self._handle_auth_reply(messages)
			#收到鉴权包，不进行处理
			OperationType.OP_HEARTBEAT_REPLY:
				self._handle_heart_beat_reply(messages)
			#收到服务器推送
			OperationType.OP_SEND_SMS_REPLY:
				self._handle_send_sms_reply(messages)
	else:
		push_error("【BILI_LIVE_WS】收到空消息")
		
#转换发送数据包的方法
func _encode_packet(content: String, operation_type:OperationType) -> PackedByteArray:
	var data_buf := content.to_utf8_buffer()
	var packet_len := data_buf.size() + PACKET_HEADER_SIZE
	var packet: PackedByteArray = PackedByteArray()
	_add_int_to_buf(packet,4,packet_len)
	_add_int_to_buf(packet,2,PACKET_HEADER_SIZE)
	_add_int_to_buf(packet,2,ProtocolVersion.V0)
	_add_int_to_buf(packet,4,operation_type)
	_add_int_to_buf(packet,4,1)
	packet.append_array(data_buf)
	return packet
# 解包的方法（处理zlib 压缩）
func _decode_packet(packet: PackedByteArray) -> PackedStringArray:
	if packet.size() < PACKET_HEADER_SIZE:
		push_error("%s size[%d] too small." % [packet, packet.size()])
		return [] as PackedStringArray
	var packet_len := _read_int_from_buf(packet, 0, 4)
#	NOTE: 这里给解压后的数据分配的空间是压缩数据的 1032 倍
#	（zlib 官方给出的理论最高压缩率是 1032:1 。）
	var data_buf := packet.slice(PACKET_HEADER_SIZE).decompress(
			packet.size() * 1032, FileAccess.COMPRESSION_DEFLATE)
#	解压缩之后数据包里面可能有很多个包连在一块，需要根据整帧长度和分包长度进行分割
	var frame_len := data_buf.size()
	var message: PackedStringArray
	while frame_len > 0:
		var sub_pkt_len := _read_int_from_buf(data_buf, 0, 4)
		var sub_pkt_data := data_buf.slice(PACKET_HEADER_SIZE, sub_pkt_len)
		message.append(sub_pkt_data.get_string_from_utf8())
		data_buf = data_buf.slice(sub_pkt_len)
		frame_len -= sub_pkt_len
		pass
	return message
#int转换为byte并追加到发包的方法
func _add_int_to_buf(packet: PackedByteArray,size:int,value: int):
	#由于所有字段[大端对齐],所以需要从前往后解析并追加到发包末尾
	for i in range(size,0,-1):
		packet.append((value >> 8 * (i - 1)) & 0xFF)
		
#从byte数组buf指定位置start开始读取bytes个字节转为int类型并返回
func _read_int_from_buf(buf: PackedByteArray, start: int, bytes: int) -> int:
	var value := 0
	if buf.size() < bytes:
		push_error("%s size[%d] too small." % [buf, buf.size()])
		return -1
	for i in range(start, start + bytes):
		value <<= 8
		value += buf[i]
	return value

#======================发送数据方法部分======================
#发送鉴权包（长连接后的第一个发包）
func _send_auth(auth_body:String):
	_ws.put_packet(_encode_packet(auth_body,OperationType.OP_AUTH))
#发送心跳包
func _send_heart_beat():
	print("发送长连接心跳包:%f" % Time.get_unix_time_from_system())
	_ws.put_packet(_encode_packet("",OperationType.OP_HEARTBEAT))
#======================处理数据的方法部分======================
#处理鉴权回复包
func _handle_auth_reply(messages:PackedStringArray):
	pass
#处理心跳回复包
func _handle_heart_beat_reply(messages:PackedStringArray):
	print("收到长连接心跳包:%f" % Time.get_unix_time_from_system())
	pass
#处理弹幕消息回复包	
func _handle_send_sms_reply(messages:PackedStringArray):
	var received_message = JSON.parse_string(String().join(messages))
	on_ws_received_message.emit(received_message)
	pass
