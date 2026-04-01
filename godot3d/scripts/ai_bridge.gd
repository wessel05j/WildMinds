extends Node
class_name AIBridge

signal decision_ready(creature_id: String, decision: Dictionary)
signal decision_failed(creature_id: String, message: String)
signal status_ready(payload: Dictionary)
signal request_failed(message: String)

var service_url := "http://127.0.0.1:8765"
var max_concurrent_requests := 2
var queued_requests: Array[Dictionary] = []
var pending_ids: Array[String] = []
var active_requests := 0
var latest_status: Dictionary = {}


func configure(url: String) -> void:
	if url.ends_with("/"):
		service_url = url.substr(0, url.length() - 1)
	else:
		service_url = url


func request_status() -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_status_completed.bind(request))
	var error := request.request(service_url + "/health")
	if error != OK:
		request.queue_free()
		emit_signal("request_failed", "Could not reach the AI helper service.")


func enqueue_decision(creature_id: String, payload: Dictionary) -> bool:
	if pending_ids.has(creature_id):
		return false
	pending_ids.append(creature_id)
	queued_requests.append({"id": creature_id, "payload": payload})
	_pump_queue()
	return true


func _pump_queue() -> void:
	while active_requests < max_concurrent_requests and not queued_requests.is_empty():
		var item: Dictionary = queued_requests.pop_front()
		var request := HTTPRequest.new()
		add_child(request)
		active_requests += 1
		request.request_completed.connect(_on_decision_completed.bind(request, str(item["id"])))
		var error := request.request(
			service_url + "/decide",
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			JSON.stringify(item["payload"])
		)
		if error != OK:
			active_requests = max(active_requests - 1, 0)
			pending_ids.erase(str(item["id"]))
			request.queue_free()
			emit_signal("decision_failed", str(item["id"]), "Could not send a decision request.")


func _on_status_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		emit_signal("request_failed", "The AI helper service returned an invalid status response.")
		return

	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(payload) != TYPE_DICTIONARY:
		emit_signal("request_failed", "The AI helper service returned malformed status data.")
		return

	latest_status = payload
	emit_signal("status_ready", payload)


func _on_decision_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request: HTTPRequest,
	creature_id: String
) -> void:
	active_requests = max(active_requests - 1, 0)
	pending_ids.erase(creature_id)
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		emit_signal("decision_failed", creature_id, "The AI helper service could not return a decision.")
		_pump_queue()
		return

	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(payload) != TYPE_DICTIONARY:
		emit_signal("decision_failed", creature_id, "The AI helper returned malformed decision data.")
		_pump_queue()
		return

	emit_signal("decision_ready", creature_id, payload)
	_pump_queue()
