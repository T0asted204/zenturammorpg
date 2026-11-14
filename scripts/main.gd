extends Node
const Rules = preload("res://scripts/world.gd")
var world = Rules.new()
var server := false
var offline := false
var state: Dictionary = {}
var my_id := 1
var elapsed := 0.0
var save_timer := 0.0
var pending := ""
var actors: Dictionary = {}
var nodes: Array = []
var drone_models: Array = []
var camera: Camera3D
var scene: Node3D
var ui: CanvasLayer
var login: PanelContainer
var hud: Control
var info: Label
var inventory: Label
var notice: Label
var offers_box: VBoxContainer
var username: LineEdit
var password: LineEdit
var endpoint: LineEdit
var login_status: Label
var sell_item: OptionButton
var price: SpinBox
var last_input := Vector2.ZERO
var input_timer := 0.0
var offer_signature := ""
var bot := false
var bot_time := 0.0
var bot_joined := false

func _ready() -> void:
 var args := OS.get_cmdline_user_args()
 server = "--server" in args
 bot = "--bot" in args
 if server:
  for a in args:
   if a.begins_with("--save="): world.save_path = a.trim_prefix("--save=")
  world.load_save()
  var peer := WebSocketMultiplayerPeer.new()
  var port := 9080
  for a in args:
   if a.begins_with("--port="): port = int(a.trim_prefix("--port="))
  var err := peer.create_server(port)
  if err != OK: push_error("Cannot listen: %s" % err); get_tree().quit(1); return
  multiplayer.multiplayer_peer = peer
  multiplayer.peer_disconnected.connect(func(id): world.leave(id); _save())
  print("ZENTURA_SERVER_READY port=", port)
  return
 multiplayer.connected_to_server.connect(_connected)
 multiplayer.connection_failed.connect(func(): _connection_error("Connection failed. Start the server or try Solo field test."))
 multiplayer.server_disconnected.connect(func(): _connection_error("Server disconnected. Reconnect to resume saved progress."))
 if bot:
  _connect_to("ws://127.0.0.1:9080")
  return
 _build_world()
 _build_ui()

func _save() -> void:
 var err: Error = world.save()
 if err != OK: push_error("Save failed: %s" % error_string(err))

func _notification(what: int) -> void:
 if what == NOTIFICATION_WM_CLOSE_REQUEST and (server or offline): _save()

func _process(dt: float) -> void:
 if server or offline:
  world.tick(dt)
  elapsed += dt; save_timer += dt
  if elapsed >= 0.1:
   elapsed = 0
   var data: Dictionary = world.snapshot()
   if offline: state = data
   else:
    for id in world.players: receive_state.rpc_id(id, data)
  if save_timer >= 5:
   save_timer = 0
   _save()
 if server: return
 if bot:
  bot_time += dt
  if bot_time > 1 and not state.is_empty() and not bot_joined:
   bot_joined = true
   request_move.rpc_id(1, -18.0, -12.0, true)
  if bot_time > 12 and bot_joined:
   request_action.rpc_id(1, "gather", "0")
  if bot_time > 14:
   var p: Dictionary = state.get("players", {}).get(my_id, {})
   if p.get("inventory", {}).get("wood", 0) >= 1:
    print("NETWORK_SMOKE_PASS ", p.name, " wood=", p.inventory.wood, " peers=", state.players.size())
    get_tree().quit()
   else: push_error("Network smoke failed"); get_tree().quit(1)
  return
 if state.is_empty(): return
 _render_state(dt)
 input_timer += dt
 if _typing() and last_input != Vector2.ZERO:
  last_input = Vector2.ZERO
  _move(0,0,false)
 if input_timer >= 0.08 and not _typing():
  input_timer = 0
  var v := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
  # Screen-relative movement for the isometric view.
  v = v.rotated(-PI / 4)
  if v != last_input:
   last_input = v
   _move(v.x, v.y, false)
 var p: Dictionary = state.players.get(my_id, {})
 if not p.is_empty() and not pending.is_empty():
  var r: Dictionary = state.resources[int(pending)]
  if Vector2(p.x - r.x, p.z - r.z).length() < 3.2:
   _action("gather", pending)
   pending = ""

func _typing() -> bool:
 return get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is SpinBox

func _connection_error(message: String) -> void:
 state = {}; pending = ""
 if bot: push_error(message); get_tree().quit(1); return
 login.show(); hud.hide(); login_status.text = message

func _connect_to(url: String) -> void:
 var peer := WebSocketMultiplayerPeer.new()
 var err := peer.create_client(url)
 if err != OK: _connection_error("Invalid WebSocket URL."); return
 multiplayer.multiplayer_peer = peer
 if not bot: login_status.text = "Connecting…"

func _connected() -> void:
 my_id = multiplayer.get_unique_id()
 if bot:
  var name_arg := "smoke"
  for a in OS.get_cmdline_user_args():
   if a.begins_with("--name="): name_arg = a.trim_prefix("--name=")
  request_join.rpc_id(1, name_arg, "smoke-test-secret")
 else: request_join.rpc_id(1, username.text, password.text)

@rpc("any_peer", "call_remote", "reliable")
func request_join(who: String, secret: String) -> void:
 if not server: return
 var id := multiplayer.get_remote_sender_id()
 var result: String = world.join(id, who, secret)
 join_result.rpc_id(id, result)
 if result.is_empty(): _save()

@rpc("authority", "call_remote", "reliable")
func join_result(error: String) -> void:
 if not error.is_empty(): _connection_error(error); return
 if not bot:
  login.hide(); hud.show()
  var cfg := ConfigFile.new()
  cfg.set_value("client", "name", username.text)
  cfg.set_value("client", "url", endpoint.text)
  cfg.save("user://client.cfg")

@rpc("any_peer", "call_remote", "reliable")
func request_move(x: float, z: float, click: bool) -> void:
 if server: world.move(multiplayer.get_remote_sender_id(), x, z, click)

@rpc("any_peer", "call_remote", "reliable")
func request_action(kind: String, arg: String) -> void:
 if server and arg.length() <= 64: world.action(multiplayer.get_remote_sender_id(), kind, arg)

@rpc("authority", "call_remote", "reliable")
func receive_state(data: Dictionary) -> void:
 state = data

func _move(x: float, z: float, click: bool) -> void:
 if offline: world.move(1, x, z, click)
 else: request_move.rpc_id(1, x, z, click)

func _action(kind: String, arg := "") -> void:
 if offline: world.action(1, kind, arg)
 else: request_action.rpc_id(1, kind, arg)

func _solo() -> void:
 offline = true
 multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
 world.save_path = "user://solo.json"
 world.load_save()
 my_id = 1
 var result: String = world.join(1, username.text, password.text)
 if not result.is_empty(): login_status.text = result; offline = false; return
 state = world.snapshot()
 login.hide(); hud.show()

func _mat(color: Color) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = 0.95
 return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 n.mesh = mesh; n.material_override = _mat(color); parent.add_child(n); n.position = pos
 return n

func _cone(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top := 0.0) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := CylinderMesh.new()
 mesh.top_radius = top; mesh.bottom_radius = radius; mesh.height = height; mesh.radial_segments = 6
 n.mesh = mesh; n.material_override = _mat(color); parent.add_child(n); n.position = pos
 return n

func _label3(parent: Node3D, text: String, pos: Vector3, color := Color.WHITE, size := 32) -> void:
 var l := Label3D.new()
 l.text = text; l.font_size = size; l.pixel_size = 0.015; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 l.modulate = color; parent.add_child(l); l.position = pos

func _build_world() -> void:
 scene = Node3D.new(); add_child(scene)
 var env := WorldEnvironment.new()
 var e := Environment.new()
 e.background_mode = Environment.BG_COLOR; e.background_color = Color("a2b8bd")
 e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("c5d7db"); e.ambient_light_energy = 0.4
 env.environment = e; scene.add_child(env)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48, -30, 0); sun.light_color = Color("ffe1ac"); sun.light_energy = 0.9
 sun.shadow_enabled = true; scene.add_child(sun)
 _box(scene, Vector3(0,-0.7,0), Vector3(58,1,60), Color("63765b"))
 _box(scene, Vector3(0,-0.15,-20), Vector3(56,0.2,18), Color("575b55"))
 _box(scene, Vector3(0,-0.1,15), Vector3(22,0.2,16), Color("a89979"))
 _box(scene, Vector3(0,0.02,0), Vector3(3,0.07,57), Color("9d947b"))
 _box(scene, Vector3(0,0.04,-10), Vector3(56,0.08,0.25), Color("dc754d"))
 _label3(scene, "ASHFALL OUTPOST  /  SAFE", Vector3(0,4,23), Color("ffe1a0"), 38)
 _label3(scene, "THE RUSTWORKS  /  PVP + DRONES", Vector3(0,4,-15), Color("ffb591"), 34)
 _label3(scene, "FOREST", Vector3(-17,3,6), Color("dfecba"))
 _label3(scene, "QUARRY", Vector3(17,3,5), Color("dfecba"))
 # Outpost workshop and trade stalls.
 for x in [-8.0, 8.0]:
  _box(scene, Vector3(x,1.2,19), Vector3(5,2.4,4), Color("77796b"))
  _box(scene, Vector3(x,2.6,19), Vector3(5.6,0.4,4.6), Color("a86443"))
  _box(scene, Vector3(x,1.1,16.8), Vector3(2.4,1.1,0.5), Color("3b4b49"))
 _box(scene, Vector3(0,0.7,17), Vector3(3,1.4,1.3), Color("594c3d"))
 _label3(scene, "WORKBENCH", Vector3(0,2.5,17), Color("f6db9f"), 22)
 # Silhouettes: rusted industrial sheds, chimneys and storage tanks.
 for x in [-19.0, 19.0]:
  _box(scene, Vector3(x,2.4,-26), Vector3(7,4.8,4), Color("745a48"))
  _box(scene, Vector3(x,4.9,-26), Vector3(7.6,0.25,4.6), Color("414d4a"))
  _cone(scene, Vector3(x+2,6,-26), 0.7, 6, Color("5b4c42"), 0.65)
 var rng := RandomNumberGenerator.new(); rng.seed = 19
 for i in range(60):
  var x := rng.randf_range(-28,28); var z := rng.randf_range(-28,28)
  _cone(scene, Vector3(x,0.12,z), rng.randf_range(0.1,0.35), 0.25, Color("7c8266"))
 for r in world.resources:
  var n := Node3D.new(); scene.add_child(n); n.position = Vector3(r.x,0,r.z); nodes.append(n)
  match r.kind:
   "wood":
    _cone(n,Vector3(0,1,0),0.3,2,Color("68503b"),0.22)
    _cone(n,Vector3(0,2.6,0),1.6,2.7,Color("325b48"))
    _cone(n,Vector3(0,3.7,0),1.15,2.0,Color("44775a"))
   "stone", "ore":
    _cone(n,Vector3(0,0.6,0),1.25,1.5,Color("8b9290") if r.kind == "stone" else Color("98725a"),0.55)
    _cone(n,Vector3(0.8,0.3,0.5),0.65,0.7,Color("a3aaa1"),0.3)
   "scrap":
    _box(n,Vector3(0,0.65,0),Vector3(1.8,1.3,1.4),Color("a36743"))
    _box(n,Vector3(0,1.4,0),Vector3(2.1,0.2,1.6),Color("5d7270"))
  _label3(n,r.kind.to_upper(),Vector3(0,4.6 if r.kind == "wood" else 2,0),Color("e3e9d1"),20)
 for d in world.drones:
  var n := Node3D.new(); scene.add_child(n); drone_models.append(n)
  _box(n,Vector3(0,0.9,0),Vector3(1.3,0.7,1),Color("a44b34"))
  _box(n,Vector3(0,1,0),Vector3(2.7,0.12,0.25),Color("363f40"))
  _label3(n,"RUST DRONE",Vector3(0,2,0),Color("ffc2a0"),20)
 camera = Camera3D.new(); scene.add_child(camera)
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 35
 camera.position = Vector3(26,32,37); camera.look_at(Vector3(0,0,8)); camera.current = true

func _panel(parent: Node, pos: Vector2, size: Vector2) -> PanelContainer:
 var panel := PanelContainer.new(); parent.add_child(panel); panel.position = pos; panel.size = size
 var style := StyleBoxFlat.new(); style.bg_color = Color("182b2e",0.95); style.border_color = Color("526461")
 style.set_border_width_all(1); style.set_corner_radius_all(6); style.content_margin_left = 16; style.content_margin_right = 16; style.content_margin_top = 12; style.content_margin_bottom = 12
 panel.add_theme_stylebox_override("panel",style)
 return panel

func _text(parent: Node, value: String, font_size := 16, color := Color("e4e6d6")) -> Label:
 var l := Label.new(); l.text = value; l.add_theme_font_size_override("font_size",font_size); l.add_theme_color_override("font_color",color); parent.add_child(l); return l

func _button(parent: Node, value: String, fn: Callable) -> Button:
 var b := Button.new(); b.text = value; b.custom_minimum_size.y = 32; b.pressed.connect(fn); parent.add_child(b); return b

func _build_ui() -> void:
 ui = CanvasLayer.new(); add_child(ui)
 var theme := Theme.new(); theme.default_font_size = 15
 var base := Control.new(); base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); base.mouse_filter = Control.MOUSE_FILTER_IGNORE; base.theme = theme; ui.add_child(base)
 hud = Control.new(); base.add_child(hud); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; hud.hide()
 var top := _panel(hud,Vector2(20,16),Vector2(1240,74))
 var row := HBoxContainer.new(); row.add_theme_constant_override("separation",28); top.add_child(row)
 _text(row,"Z E N T U R A",27,Color("efca88"))
 info = _text(row,"",16)
 var side := _panel(hud,Vector2(1000,104),Vector2(260,662))
 var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(228,630); side.add_child(scroll)
 var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(col)
 _text(col,"FIELD PACK",20,Color("efca88"))
 inventory = _text(col,"")
 _text(col,"SUPPLIES",16,Color("90b5a3"))
 var supplies := HBoxContainer.new(); col.add_child(supplies)
 _button(supplies,"Eat ration",func(): _action("use","ration"))
 _button(supplies,"Bandage",func(): _action("use","bandage"))
 _text(col,"WORKBENCH / OUTPOST",16,Color("efca88"))
 for item in Rules.RECIPES:
  var parts: Array[String] = []
  for cost in Rules.RECIPES[item]: parts.append("%d %s" % [Rules.RECIPES[item][cost],cost])
  var b := _button(col,"Craft " + item + (" ×6" if item == "ammo" else ""),_action.bind("craft",item))
  b.tooltip_text = " + ".join(parts)
  _text(col," + ".join(parts),12,Color("a1b6ae"))
 _text(col,"PLAYER MARKET / SAFE ZONE",16,Color("efca88"))
 sell_item = OptionButton.new(); col.add_child(sell_item)
 for item in Rules.ITEMS: sell_item.add_item(item)
 price = SpinBox.new(); price.min_value = 1; price.max_value = 999; price.value = 5; price.prefix = "Coins "; col.add_child(price)
 _button(col,"Offer one item",func(): _action("sell",Rules.ITEMS[sell_item.selected] + ":" + str(int(price.value))))
 _button(col,"Cancel my offer",func(): _action("cancel"))
 offers_box = VBoxContainer.new(); col.add_child(offers_box)
 _button(col,"Salvage contract • scrap > 8 coins",func(): _action("salvage"))
 var bottom := _panel(hud,Vector2(20,658),Vector2(955,108))
 var bc := VBoxContainer.new(); bottom.add_child(bc)
 notice = _text(bc,"",17,Color("efca88"))
 _text(bc,"WASD / click ground: move   •   Click resource: approach & gather   •   E: gather nearest",14)
 _text(bc,"Click drone / player: attack   •   North of red line: PvP   •   Wheel: zoom   •   Esc: release focus",14)
 login = _panel(base,Vector2(355,150),Vector2(570,470))
 var lc := VBoxContainer.new(); lc.add_theme_constant_override("separation",10); login.add_child(lc)
 _text(lc,"Z E N T U R A",36,Color("efca88"))
 _text(lc,"ASHFALL FRONTIER   /   Multiplayer prototype",18)
 _text(lc,"Build a life from the wreckage.\nGather > craft > brave the rustworks > trade.",16)
 username = LineEdit.new(); username.placeholder_text = "Character name (3–16 letters / numbers)"; username.text = "survivor"; lc.add_child(username)
 password = LineEdit.new(); password.placeholder_text = "Passphrase (8+ characters, needed to return)"; password.secret = true; lc.add_child(password)
 endpoint = LineEdit.new(); endpoint.text = "ws://127.0.0.1:9080"; lc.add_child(endpoint)
 var cfg := ConfigFile.new()
 if cfg.load("user://client.cfg") == OK:
  username.text = cfg.get_value("client","name","survivor"); endpoint.text = cfg.get_value("client","url",endpoint.text)
 _button(lc,"ENTER SHARED WORLD",func(): _connect_to(endpoint.text.strip_edges()))
 _button(lc,"SOLO FIELD TEST  /  local save",_solo)
 login_status = _text(lc,"New name creates a character. Reuse your passphrase to return.",13)
 login_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _text(lc,"Solo saves stay in this browser. Shared worlds need a running server.",12,Color("9cb5ad"))

func _render_state(dt: float) -> void:
 for id in actors.keys():
  if not state.players.has(id): actors[id].queue_free(); actors.erase(id)
 for id in state.players:
  var p: Dictionary = state.players[id]
  if not actors.has(id):
   var n := Node3D.new(); scene.add_child(n); actors[id] = n
   _cone(n,Vector3(0,0.8,0),0.42,1.15,Color("cf9b54") if id == my_id else Color("639b9e"),0.55)
   _box(n,Vector3(0,1.65,0),Vector3(0.58,0.6,0.58),Color("d6b894"))
   _box(n,Vector3(0,1.98,0),Vector3(0.68,0.15,0.68),Color("3b514c"))
   for x in [-0.22,0.22]: _box(n,Vector3(x,0.2,0),Vector3(0.26,0.5,0.3),Color("374744"))
   _label3(n,p.name,Vector3(0,2.8,0),Color("ffe2a2") if id == my_id else Color.WHITE,22)
   n.position = Vector3(p.x,0,p.z)
  actors[id].position = actors[id].position.lerp(Vector3(p.x,0,p.z),minf(1,dt*15))
 for i in range(nodes.size()): nodes[i].scale = Vector3.ONE * (1.0 if state.resources[i].left > 0 else 0.22)
 for i in range(drone_models.size()):
  var d: Dictionary = state.drones[i]
  drone_models[i].visible = d.hp > 0
  drone_models[i].position = Vector3(d.x,0,d.z)
 var p: Dictionary = state.players.get(my_id,{})
 if p.is_empty(): return
 var pos := Vector3(p.x,0,p.z)
 camera.position = camera.position.lerp(pos + Vector3(24,30,24),minf(1,dt*4))
 camera.look_at(pos)
 info.text = "%s   |   HP %d   FOOD %d   |   %d coins   |   %s\nGathering Lv%d   Engineering Lv%d   Combat Lv%d   •   %d online" % [p.name,p.hp,p.food,p.coins,"DANGER / PVP" if p.z < -10 else "SAFE TERRITORY",1+int(p.xp.gathering/100),1+int(p.xp.engineering/100),1+int(p.xp.combat/100),state.players.size()]
 var lines := ""
 for item in Rules.ITEMS:
  if p.inventory.get(item,0) > 0: lines += "%s   ×%d\n" % [item.capitalize(),p.inventory[item]]
 inventory.text = lines
 notice.text = p.message
 var sig := str(state.offers)
 if sig != offer_signature:
  offer_signature = sig
  for child in offers_box.get_children(): child.queue_free()
  for id in state.offers:
   var o: Dictionary = state.offers[id]
   _button(offers_box,"%s: %s / %d coins" % [o.seller,o.item,o.price],_action.bind("buy",str(id)))

func _unhandled_input(event: InputEvent) -> void:
 if state.is_empty() or bot: return
 if event is InputEventKey and event.pressed:
  if event.keycode == KEY_ESCAPE:
   var focus := get_viewport().gui_get_focus_owner()
   if focus: focus.release_focus()
  if event.keycode == KEY_E and not _typing():
   var p: Dictionary = state.players.get(my_id,{})
   var best := -1; var dist := 3.6
   for r in state.resources:
    var d := Vector2(p.x-r.x,p.z-r.z).length()
    if d < dist and r.left > 0: best = r.id; dist = d
   if best >= 0: _action("gather",str(best))
 if event is InputEventMouseButton and event.pressed:
  if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(18,camera.size-2)
  if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(55,camera.size+2)
  if event.button_index != MOUSE_BUTTON_LEFT: return
  var point: Vector2 = event.position
  var hit = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
  if hit == null: return
  pending = ""
  for d in state.drones:
   if d.hp > 0 and Vector2(hit.x-d.x,hit.z-d.z).length() < 2: _action("drone",str(d.id)); return
  for id in state.players:
   var p: Dictionary = state.players[id]
   if id != my_id and Vector2(hit.x-p.x,hit.z-p.z).length() < 1.5: _action("pvp",str(id)); return
  for r in state.resources:
   if point.distance_to(camera.unproject_position(Vector3(r.x,2.0 if r.kind == "wood" else 0.8,r.z))) < 32 or Vector2(hit.x-r.x,hit.z-r.z).length() < 2:
    pending = str(r.id); _move(r.x,r.z,true); return
  _move(hit.x,hit.z,true)
