extends RefCounted
## Server-only rules. No client can supply inventory, damage, position or XP.
const ITEMS = ["wood", "stone", "ore", "scrap", "metal", "axe", "pickaxe", "spear", "pistol", "ammo", "bandage", "ration"]
const RECIPES = {
 "axe": {"wood": 3, "stone": 2},
 "pickaxe": {"wood": 3, "stone": 3},
 "metal": {"ore": 2, "wood": 1},
 "spear": {"wood": 4, "metal": 1},
 "pistol": {"metal": 4, "scrap": 3},
 "ammo": {"metal": 1, "scrap": 1},
 "bandage": {"wood": 2, "scrap": 1},
 "ration": {"wood": 2}
}
var players: Dictionary = {}
var accounts: Dictionary = {}
var resources: Array = []
var offers: Dictionary = {}
var drones: Array = []
var now := 0.0
var save_path := "user://world.json"
var dirty := false

func _init() -> void:
 for i in range(18):
  var kind: String = ["wood", "stone", "ore", "scrap"][i % 4]
  var x: float = -18.0 + float(i % 6) * 7.0
  var z: float = -12.0 + float(i / 6) * 10.0
  if kind == "scrap": z = -20.0
  resources.append({"id": i, "kind": kind, "x": x, "z": z, "left": 5, "respawn": 0.0})
 for i in range(3):
  drones.append({"id": i, "x": -12.0 + i * 12.0, "z": -23.0, "hp": 45, "respawn": 0.0, "cool": 0.0})

func load_save() -> void:
 if not FileAccess.file_exists(save_path): return
 var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
 if not data is Dictionary: return
 accounts = data.get("accounts", {})
 var saved: Array = data.get("resources", [])
 if saved.size() == resources.size():
  resources = saved
  # Convert relative respawn durations back to server clock.
  for r in resources: r.respawn = now + float(r.respawn)

func save() -> Error:
 for p in players.values(): _store(p)
 var saved := resources.duplicate(true)
 for r in saved: r.respawn = maxf(0.0, r.respawn - now)
 var f := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
 if f == null: return FileAccess.get_open_error()
 f.store_string(JSON.stringify({"version": 1, "accounts": accounts, "resources": saved}))
 f.close()
 var err := DirAccess.rename_absolute(save_path + ".tmp", save_path)
 if err == OK: dirty = false
 return err

func _store(p: Dictionary) -> void:
 var saved_inventory: Dictionary = p.inventory.duplicate()
 if offers.has(p.id):
  var item: String = offers[p.id].item
  saved_inventory[item] = saved_inventory.get(item, 0) + 1
 accounts[p.name] = {"key": p.key, "x": p.x, "z": p.z, "hp": p.hp, "food": p.food, "inventory": saved_inventory, "xp": p.xp.duplicate(), "coins": p.coins}

func join(id: int, username: String, secret: String) -> String:
 username = username.strip_edges().to_lower()
 if username.length() < 3 or username.length() > 16 or not username.is_valid_identifier(): return "Use 3–16 letters, numbers or underscores; start with a letter."
 if secret.length() < 8 or secret.length() > 128: return "Use a passphrase of 8–128 characters. Keep it to resume your character."
 if players.has(id): return "Already joined."
 if players.size() >= 32: return "Prototype server full (32 players)."
 for p in players.values():
  if p.name == username: return "Character already online."
 var key := (username + ":zentura:" + secret).sha256_text()
 if accounts.has(username) and accounts[username].key != key: return "Wrong passphrase for this character."
 var p: Dictionary = accounts.get(username, {"key": key, "x": 0.0, "z": 15.0, "hp": 100.0, "food": 100.0, "inventory": {"ration": 3}, "xp": {"gathering": 0, "engineering": 0, "combat": 0}, "coins": 25}).duplicate(true)
 p.merge({"name": username, "id": id, "dx": 0.0, "dz": 0.0, "target": [], "cool": 0.0, "message": "Welcome to Ashfall. Gather, craft, survive, trade."}, true)
 players[id] = p
 dirty = true
 return ""

func leave(id: int) -> void:
 if not players.has(id): return
 cancel_offer(id)
 _store(players[id])
 players.erase(id)
 dirty = true

func distance(a: Dictionary, b: Dictionary) -> float:
 return Vector2(a.x - b.x, a.z - b.z).length()

func move(id: int, x: float, z: float, click: bool) -> void:
 if not players.has(id) or not is_finite(x) or not is_finite(z): return
 var p: Dictionary = players[id]
 if click:
  p.target = [clampf(x, -27, 27), clampf(z, -28, 27)]
 else:
  var v := Vector2(x, z).limit_length()
  p.dx = v.x
  p.dz = v.y
  if v.length() > 0: p.target = []

func tick(dt: float) -> void:
 now += dt
 for r in resources:
  if r.left <= 0 and now >= r.respawn: r.left = 5
 for p in players.values():
  var v := Vector2(p.dx, p.dz)
  if p.target.size() == 2:
   var delta := Vector2(p.target[0] - p.x, p.target[1] - p.z)
   if delta.length() < 0.3: p.target = []
   else: v = delta.normalized()
  p.x = clampf(p.x + v.x * dt * 6, -27, 27)
  p.z = clampf(p.z + v.y * dt * 6, -28, 27)
  p.food = maxf(0, p.food - dt * 0.08)
  if p.food <= 0: p.hp -= dt * 0.7
  elif p.z > 9: p.hp = minf(100, p.hp + dt * 2)
  if p.hp <= 0: _die(p)
 for d in drones:
  if d.hp <= 0:
   if now >= d.respawn: d.hp = 45
   continue
  var nearest: Dictionary = {}
  var dist := 12.0
  for p in players.values():
   if p.z >= -10: continue
   var n := distance(p, d)
   if n < dist: nearest = p; dist = n
  if nearest.is_empty(): continue
  if dist > 2:
   var v := Vector2(nearest.x - d.x, nearest.z - d.z).normalized()
   d.x = clampf(d.x + v.x * dt * 2.5, -26, 26)
   d.z = clampf(d.z + v.y * dt * 2.5, -28, -11)
  elif now >= d.cool:
   d.cool = now + 1.5
   nearest.hp -= 9
   nearest.message = "A rust drone strikes! Retreat south to the outpost."
   if nearest.hp <= 0: _die(nearest)

func _die(p: Dictionary) -> void:
 p.hp = 100.0; p.food = 70.0; p.x = 0.0; p.z = 15.0; p.target = []
 p.coins = maxi(0, p.coins - 10)
 p.message = "Rescued at the outpost. Lost up to 10 coins. Equipment retained."
 dirty = true

func action(id: int, kind: String, arg: String = "") -> void:
 if not players.has(id): return
 var p: Dictionary = players[id]
 if now < p.cool: return
 p.cool = now + 0.35
 dirty = true
 match kind:
  "gather":
   if not arg.is_valid_int(): return
   var index := int(arg)
   if index < 0 or index >= resources.size(): return
   var r: Dictionary = resources[index]
   if distance(p, r) > 3.5: p.message = "Move closer to the resource."; return
   if r.left <= 0: p.message = "Depleted. This node regrows in 30 seconds."; return
   r.left -= 1
   if r.left == 0: r.respawn = now + 30
   var tool: String = "axe" if r.kind == "wood" else "pickaxe"
   var amount := 2 if p.inventory.get(tool, 0) > 0 else 1
   _add(p, r.kind, amount)
   p.xp.gathering += 12
   p.cool = now + 1.0
   p.message = "+%d %s • +12 gathering XP" % [amount, r.kind]
  "craft":
   if not RECIPES.has(arg): return
   if distance(p, {"x": 0.0, "z": 15.0}) > 8: p.message = "Craft at the outpost workbench."; return
   var costs: Dictionary = RECIPES[arg]
   for item in costs:
    if p.inventory.get(item, 0) < costs[item]: p.message = "Missing materials for " + arg; return
   for item in costs: _add(p, item, -costs[item])
   _add(p, arg, 6 if arg == "ammo" else 1)
   p.xp.engineering += 20
   p.message = "Crafted %s • +20 engineering XP" % arg
  "use":
   if arg not in ["ration", "bandage"] or p.inventory.get(arg, 0) < 1: return
   _add(p, arg, -1)
   if arg == "ration": p.food = minf(100, p.food + 35)
   else: p.hp = minf(100, p.hp + 35)
   p.message = "Used " + arg
  "drone", "pvp": _attack(p, kind, arg)
  "sell":
   var parts := arg.split(":")
   if parts.size() != 2 or parts[0] not in ITEMS or not parts[1].is_valid_int(): return
   var price := int(parts[1])
   if price < 1 or price > 999 or p.z < 9 or p.inventory.get(parts[0], 0) < 1: p.message = "Sell one owned item at the outpost, price 1–999."; return
   cancel_offer(id)
   _add(p, parts[0], -1)
   offers[id] = {"seller": p.name, "item": parts[0], "price": price}
   p.message = "Offer posted. One item held in escrow."
  "cancel": cancel_offer(id)
  "buy":
   if not arg.is_valid_int(): return
   var seller := int(arg)
   if seller == id or not offers.has(seller) or not players.has(seller) or p.z < 9: return
   var o: Dictionary = offers[seller]
   if p.coins < o.price: p.message = "Not enough coins."; return
   p.coins -= o.price
   players[seller].coins += o.price
   _add(p, o.item, 1)
   offers.erase(seller)
   p.message = "Bought %s from %s." % [o.item, o.seller]
  "salvage":
   if p.z > -15: p.message = "Salvage pays out in the northern scrapyard."; return
   if p.inventory.get("scrap", 0) < 1: p.message = "Bring one scrap to exchange for 8 coins."; return
   _add(p, "scrap", -1); p.coins += 8
   p.message = "Salvage contract: +8 coins."

func _attack(p: Dictionary, kind: String, arg: String) -> void:
 if not arg.is_valid_int(): return
 var index := int(arg)
 var target: Dictionary = {}
 if kind == "drone" and index >= 0 and index < drones.size(): target = drones[index]
 if kind == "pvp" and players.has(index) and index != p.id: target = players[index]
 if target.is_empty() or target.hp <= 0: return
 if p.z >= -10 or target.z >= -10: p.message = "Combat is only allowed north of the red boundary."; return
 var gun: bool = p.inventory.get("pistol", 0) > 0 and p.inventory.get("ammo", 0) > 0
 if distance(p, target) > (11.0 if gun else 3.5): p.message = "Target out of range."; return
 if gun: _add(p, "ammo", -1)
 var damage := 24 if gun else (15 if p.inventory.get("spear", 0) > 0 else 6)
 target.hp -= damage
 p.cool = now + 1
 p.xp.combat += 10
 p.message = "Hit for %d • +10 combat XP" % damage
 if target.hp <= 0:
  if kind == "drone":
   target.respawn = now + 25; _add(p, "scrap", 3); p.coins += 12
   p.message = "Drone disabled: +3 scrap, +12 coins."
  else: _die(target)

func _add(p: Dictionary, item: String, amount: int) -> void:
 p.inventory[item] = p.inventory.get(item, 0) + amount
 if p.inventory[item] <= 0: p.inventory.erase(item)

func cancel_offer(id: int) -> void:
 if offers.has(id) and players.has(id):
  _add(players[id], offers[id].item, 1)
  offers.erase(id)

func snapshot() -> Dictionary:
 var visible := {}
 for id in players:
  var p: Dictionary = players[id].duplicate(true)
  p.erase("key")
  visible[id] = p
 return {"players": visible, "resources": resources, "drones": drones, "offers": offers}
