#!/usr/bin/lua

local uci = require "uci"
local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
local nixio = require "nixio"

local CFG = "passwall_device"
local PW = "passwall"
local cursor = uci.cursor()

local function reply(t)
	io.write(jsonc.stringify(t or {}), "\n")
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function scalar(value, fallback)
	if type(value) == "table" then value = value[1] end
	if value == nil or value == "" then value = fallback end
	return tostring(value or "")
end

local function shellquote(s)
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function valid_id(s)
	return tostring(s or ""):match("^[%w_%-]+$") ~= nil
end

local function parse_ids(value)
	local text_value = tostring(value or "")
	if text_value:find("[^%w_,%-%s]") then return nil end
	local ids, seen = {}, {}
	for id in text_value:gmatch("[^,%s]+") do
		if valid_id(id) and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	return ids
end

local function percent_encode(s)
	return (tostring(s or ""):gsub("([^%w%-_%.~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function percent_decode(s)
	return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- 拆分 "链接#备注---口令1 口令2 口令3" 中的显式口令
local function split_link_codes(value)
	local link, suffix = tostring(value or ""):match("^(.-)%-%-%-(.-)$")
	if not suffix then return tostring(value or ""), nil end
	local list = {}
	for code in tostring(suffix):gmatch("[^%s,，]+") do
		code = trim(code)
		if code ~= "" then list[#list + 1] = code end
	end
	return trim(link), (#list > 0) and list or nil
end

local section_counter = 0
local function new_section(c, config, section_type, prefix, values)
	section_counter = section_counter + 1
	local id
	repeat
		-- 定制 Lua（double int32）里 %x 要求整数，2^32 取模会变成浮点数，改用 2^31-1
		id = (prefix or "pwc_") .. string.format("%08x%04x%02x", os.time() % 2147483647, nixio.getpid() % 65536, section_counter % 256)
		section_counter = section_counter + 1
	until not c:get(config, id)
	c:set(config, id, section_type)
	for key, value in pairs(values or {}) do c:set(config, id, key, tostring(value)) end
	return id
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

local function node_map(c)
	local out = {}
	c:foreach(PW, "nodes", function(s)
		out[s[".name"]] = s
	end)
	return out
end

local function metadata_for_node(c, node_id)
	local found
	c:foreach(CFG, "node", function(s)
		if s.passwall_id == node_id then found = s end
	end)
	return found
end

local function code_value_less(a, b)
	a, b = tostring(a or ""), tostring(b or "")
	local an, bn = tonumber(a), tonumber(b)
	if an and bn and an ~= bn then return an < bn end
	return a < b
end

local function codes_for_node(c, node_id)
	local found = {}
	c:foreach(CFG, "code", function(s)
		if s.node_id == node_id then found[#found + 1] = s end
	end)
	table.sort(found, function(a, b)
		if a.value ~= b.value then return code_value_less(a.value, b.value) end
		return (a.created_at or a[".name"]) < (b.created_at or b[".name"])
	end)
	return found
end

local function code_by_value(c, value)
	local found
	c:foreach(CFG, "code", function(s) if s.value == value then found = s end end)
	return found
end

local function binding_for_mac(c, mac)
	local found
	c:foreach(CFG, "binding", function(s)
		if (s.mac or ""):lower() == (mac or ""):lower() then found = s end
	end)
	return found
end

local function bindings_for_node(c, node_id)
	local found = {}
	c:foreach(CFG, "binding", function(s)
		if s.node_id == node_id then found[#found + 1] = s end
	end)
	return found
end

local function binding_for_code(c, code_id)
	local found
	c:foreach(CFG, "binding", function(s)
		if s.code_id == code_id then found = s end
	end)
	return found
end

local function find_node_by_remark(c, remark)
	local found
	c:foreach(PW, "nodes", function(s)
		if s.remarks == remark then found = s end
	end)
	return found
end

local function wifi_clients()
	local clients = {}
	local scanned = false
	local objects = sys.exec("ubus list 'hostapd.*' 2>/dev/null") or ""
	for object in objects:gmatch("[^\r\n]+") do
		object = trim(object)
		if object:match("^hostapd%.[%w_.%-]+$") then
			local data = jsonc.parse(sys.exec("ubus call " .. shellquote(object) .. " get_clients 2>/dev/null") or "")
			if type(data) == "table" and type(data.clients) == "table" then
				scanned = true
				for mac, info in pairs(data.clients) do
					if tostring(mac):match("^[%x][%x]:[%x][%x]:[%x][%x]:[%x][%x]:[%x][%x]:[%x][%x]$") and
					   (type(info) ~= "table" or info.assoc ~= false) then
						clients[mac:lower()] = true
					end
				end
			end
		end
	end
	return clients, scanned
end

local function wifi_mac_list()
	local clients, scanned = wifi_clients()
	local macs = {}
	for mac in pairs(clients) do macs[#macs + 1] = mac end
	table.sort(macs)
	return {ok=true, scanned=scanned, macs=macs}
end

local function list_status()
	local c = uci.cursor()
	local nodes = {}
	local bindings = {}
	local binding_groups = {}
	local pw_nodes = node_map(c)
	local wireless, wireless_scanned = wifi_clients()
	c:foreach(CFG, "binding", function(s)
		local p = pw_nodes[s.node_id]
		local online = wireless[(s.mac or ""):lower()] == true
		local display_name = trim(s.remark) ~= "" and s.remark or (s.hostname or "未知设备")
		local item = {
			id=s[".name"], mac=s.mac or "", ip=s.ip or "", hostname=display_name,
			system_hostname=s.hostname or "", remark=s.remark or "",
			node_id=s.node_id or "", code_id=s.code_id or "", code=s.code or "",
			node=p and (p.remarks or s.node_id) or "节点已删除",
			state=s.state or "active", bound_at=s.bound_at or "", online=online
		}
		bindings[#bindings + 1] = item
		binding_groups[s.node_id or ""] = binding_groups[s.node_id or ""] or {}
		binding_groups[s.node_id or ""][#binding_groups[s.node_id or ""] + 1] = item
	end)
	c:foreach(CFG, "node", function(s)
		local p = pw_nodes[s.passwall_id]
		if p then
			local group = binding_groups[s.passwall_id] or {}
			local online_count, names = 0, {}
			for _, b in ipairs(group) do
				if b.online then online_count = online_count + 1 end
				names[#names + 1] = b.hostname
			end
			local code_items = {}
			for _, code in ipairs(codes_for_node(c, s.passwall_id)) do
				local binding = binding_for_code(c, code[".name"])
				code_items[#code_items + 1] = {
					id=code[".name"], value=code.value or "", bound=binding ~= nil,
					device=binding and (trim(binding.remark) ~= "" and binding.remark or binding.hostname or binding.mac) or "",
					online=binding and wireless[(binding.mac or ""):lower()] == true or false
				}
			end
			nodes[#nodes + 1] = {
				id=s.passwall_id, meta_id=s[".name"], remarks=p.remarks or s.remarks or s.passwall_id,
				protocol=p.protocol or "", type=p.type or "", address=p.address or "", port=p.port or "",
				codes=code_items, code_count=#code_items, bound=#group > 0, device_count=#group, online_count=online_count,
				last_test_at=s.last_test_at or "", last_reachable=s.last_reachable or "",
				last_exit_ip=s.last_exit_ip or "", last_test_message=s.last_test_message or "",
				devices=names, online=online_count > 0, state=#group > 0 and "active" or "free"
			}
		end
	end)
	table.sort(nodes, function(a,b)
		local ac = a.codes[1] and a.codes[1].value or ""
		local bc = b.codes[1] and b.codes[1].value or ""
		if ac ~= bc then
			if ac == "" then return false end
			if bc == "" then return true end
			return code_value_less(ac, bc)
		end
		return a.remarks < b.remarks
	end)
	table.sort(bindings, function(a,b) return a.bound_at > b.bound_at end)
	return {
		ok=true,
		enabled=c:get(CFG, "global", "enabled") == "1",
		passwall_enabled=c:get(PW, "@global[0]", "enabled") == "1",
		nodes=nodes, bindings=bindings,
		lan_ip=(scalar(c:get("network", "lan", "ipaddr"), "10.0.0.1"):gsub("/.*$", "")),
		version=trim(read_file("/usr/share/passwall-device/VERSION") or "0.6.0"),
		wireless_scanned=wireless_scanned,
		offline_unbind_seconds=tonumber((c:get(CFG, "global", "offline_unbind_seconds"))) or 60,
		logs=trim(sys.exec("logread -e passwall-device 2>/dev/null | tail -n 50") or "")
	}
end

local function extract_links(text)
	local links, errors, seen, link_codes = {}, {}, {}, {}
	local accepted = {vmess=true, vless=true, trojan=true, ["trojan-go"]=true, ss=true, socks=true, socks5=true}
	local function add(value)
		value = trim(value):gsub("[,;%)%]，；。]+$", "")
		local clean, explicit = split_link_codes(value)
		if clean ~= "" and not seen[clean] then
			seen[clean] = true
			links[#links + 1] = clean
			link_codes[#links] = explicit
		end
	end
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local found = false
		for scheme, value in line:gmatch("([%a][%w+.-]*)://(.+)$") do
			scheme = scheme:lower()
			if accepted[scheme] then add(scheme .. "://" .. value); found = true end
		end
		if not found then
			local clean = trim(line)
			local host, port, user, pass = clean:match("^([%w%.%-]+):(%d+):([^:]+):(.+)$")
			if host and tonumber(port) and tonumber(port) <= 65535 then
				add("socks5://" .. percent_encode(user) .. ":" .. percent_encode(pass) .. "@" .. host .. ":" .. port)
				found = true
			else
				host, port = clean:match("^([%w%.%-]+):(%d+)$")
				if host and tonumber(port) and tonumber(port) <= 65535 then add("socks5://" .. host .. ":" .. port); found = true end
			end
		end
		if not found and trim(line) ~= "" then errors[#errors+1] = trim(line) end
	end
	return links, errors, link_codes
end

local function parse_socks_link(link)
	local scheme, rest = tostring(link):match("^(socks5?)://(.+)$")
	if not scheme then return nil end
	local fragment
	rest, fragment = rest:match("^(.-)#(.*)$") or rest, rest:match("^.-#(.*)$")
	local auth, endpoint = rest:match("^(.-)@(.+)$")
	if not endpoint then endpoint = rest; auth = nil end
	endpoint = endpoint:gsub("%?.*$", "")
	local host, port = endpoint:match("^%[([^%]]+)%]:(%d+)$")
	if not host then host, port = endpoint:match("^([^:]+):(%d+)$") end
	port = tonumber(port or "")
	if not host or not port or port < 1 or port > 65535 then return nil end
	local username, password = "", ""
	if auth and auth ~= "" then
		username, password = auth:match("^([^:]*):(.*)$")
		if not username then
			local encoded = auth:gsub("-", "+"):gsub("_", "/")
			encoded = encoded .. string.rep("=", (4 - #encoded % 4) % 4)
			local ok, decoded = pcall(nixio.bin.b64decode, encoded)
			if ok and decoded then username, password = decoded:match("^([^:]*):(.*)$") end
		end
	end
	return {
		host=percent_decode(host), port=port, username=percent_decode(username or ""),
		password=percent_decode(password or ""), remarks=percent_decode(fragment or "")
	}
end

local function code_in_use(c, value)
	if code_by_value(c, value) then return true end
	local used = false
	c:foreach(CFG, "node", function(s) if s.code == value then used = true end end)
	return used
end

local function create_codes(c, node_ids, code_prefix, code_start, code_width, count_each)
	code_prefix = tostring(code_prefix or "")
	local number = math.max(0, tonumber(code_start) or 1)
	local width = math.min(12, math.max(1, tonumber(code_width) or 3))
	local count = math.min(100, math.max(1, tonumber(count_each) or 1))
	local created = {}
	for _, node_id in ipairs(node_ids) do
		for _ = 1, count do
			local value
			repeat
				value = code_prefix .. string.format("%0" .. tostring(width) .. "d", number)
				number = number + 1
			until not code_in_use(c, value)
			local id = new_section(c, CFG, "code", "pwc_code_", {
				node_id=node_id, value=value, created_at=os.date("%Y-%m-%d %H:%M:%S") .. string.format(".%06d", #created + 1)
			})
			created[#created + 1] = {id=id, node_id=node_id, value=value}
		end
	end
	c:set(CFG, "global", "code_prefix", code_prefix)
	c:set(CFG, "global", "code_width", tostring(width))
	c:set(CFG, "global", "next_code_number", tostring(number))
	return created, number
end

local function create_explicit_codes(c, node_id, values)
	local created = {}
	for _, raw in ipairs(values or {}) do
		local value = trim(raw)
		if value ~= "" and #value <= 64 and not code_in_use(c, value) then
			local id = new_section(c, CFG, "code", "pwc_code_", {
				node_id=node_id, value=value,
				created_at=os.date("%Y-%m-%d %H:%M:%S") .. string.format(".%06d", #created + 1)
			})
			created[#created + 1] = {id=id, node_id=node_id, value=value}
		end
	end
	return created
end

local function import_nodes(path, prefix, start_number, code_prefix, code_start, code_width, code_count)
	local text = read_file(path)
	if not text then return {ok=false, error="无法读取导入内容"} end
	local links, ignored, link_codes = extract_links(text)
	if #links == 0 then return {ok=false, error="没有找到 VMess、VLESS、Trojan、Trojan-Go、SS 或 SOCKS 节点"} end
	local before = node_map(uci.cursor())
	local official = {}
	local official_codes = {}
	local socks_cursor = uci.cursor()
	local socks_explicit = {}
	for i, link in ipairs(links) do
		local socks = parse_socks_link(link)
		if socks then
			local id = new_section(socks_cursor, PW, "nodes", "pwc_node_", {
				remarks=socks.remarks ~= "" and socks.remarks or ("SOCKS " .. socks.host .. ":" .. socks.port),
				type="Xray", protocol="socks", address=socks.host, port=socks.port,
				username=socks.username, password=socks.password
			})
			if link_codes[i] then socks_explicit[#socks_explicit + 1] = {id=id, codes=link_codes[i]} end
		else
			-- PassWall parses Trojan links but does not recognize the historical
			-- trojan-go scheme. Normalize only the scheme and preserve the WS/TLS
			-- query parameters for its official parser.
			official[#official+1] = link:gsub("^trojan%-go://", "trojan://", 1)
			if link_codes[i] then official_codes[#official_codes + 1] = link_codes[i] end
		end
	end
	socks_cursor:commit(PW)
	if #official > 0 then
		local tmp = "/tmp/links.conf"
		local f = io.open(tmp, "w")
		if not f then return {ok=false, error="无法写入 PassWall 导入文件"} end
		f:write(table.concat(official, "\n"), "\n")
		f:close()
		os.execute("lua /usr/share/passwall/subscribe.lua add pwc >/tmp/pwc-import.log 2>&1")
	end
	local c = uci.cursor()
	local added = {}
	-- UCI foreach preserves the order written by PassWall's importer. The
	-- generated section names are random, so sorting by .name would scramble
	-- the node-to-code relationship even though codes look sequential.
	c:foreach(PW, "nodes", function(n)
		if not before[n[".name"]] then added[#added + 1] = n end
	end)
	if #added == 0 then
		return {ok=false, error="PassWall 未添加节点，可能全部重复或格式不受支持", details=trim(read_file("/tmp/pwc-import.log") or "")}
	end
	start_number = math.max(0, tonumber(start_number) or 1)
	code_start = math.max(0, tonumber(code_start) or 1)
	code_width = math.min(12, math.max(1, tonumber(code_width) or 3))
	code_count = math.min(100, math.max(1, tonumber(code_count) or 1))
	local results, auto_node_ids = {}, {}
	local has_sing_box = sys.call("test -x /usr/bin/sing-box") == 0
	-- socks 节点在前、官方解析节点在后的显式口令队列
	local explicit_queue = {}
	for _, item in ipairs(socks_explicit) do explicit_queue[#explicit_queue + 1] = item end
	for _, codes in ipairs(official_codes) do explicit_queue[#explicit_queue + 1] = {codes=codes} end
	for i, n in ipairs(added) do
		local remark = n.remarks or n[".name"]
		if trim(prefix) ~= "" then remark = trim(prefix) .. tostring(start_number + i - 1) end
		if find_node_by_remark(c, remark) and (find_node_by_remark(c, remark)[".name"] ~= n[".name"]) then
			remark = remark .. "-" .. tostring(i)
		end
		-- Prefer sing-box for imported SOCKS nodes and protocol variants that have
		-- shown core-specific compatibility differences during health checks.
		local is_trojan = n.protocol == "trojan" or n.type == "Trojan-Plus"
		if has_sing_box and ((n.protocol == "vless" and n.reality == "1") or is_trojan or n.protocol == "socks") then
			c:set(PW, n[".name"], "type", "sing-box")
			n.type = "sing-box"
			if is_trojan then
				c:set(PW, n[".name"], "protocol", "trojan")
				n.protocol = "trojan"
			end
		end
		c:set(PW, n[".name"], "remarks", remark)
		new_section(c, CFG, "node", "pwc_meta_", {passwall_id=n[".name"], remarks=remark, created_at=os.date("%Y-%m-%d %H:%M:%S")})
		local result = {id=n[".name"], remarks=remark, protocol=n.protocol or "", codes={}}
		if explicit_queue[i] then
			result.explicit_codes = explicit_queue[i].codes
		else
			auto_node_ids[#auto_node_ids + 1] = n[".name"]
		end
		results[#results+1] = result
	end
	local created = create_codes(c, auto_node_ids, code_prefix, code_start, code_width, code_count)
	local explicit_created = {}
	for _, result in ipairs(results) do
		if result.explicit_codes then
			local items = create_explicit_codes(c, result.id, result.explicit_codes)
			local values = {}
			for _, item in ipairs(items) do values[#values + 1] = item.value end
			result.codes = values
			for _, item in ipairs(items) do explicit_created[#explicit_created + 1] = item end
		end
	end
	local by_node = {}
	for _, item in ipairs(created) do
		by_node[item.node_id] = by_node[item.node_id] or {}
		by_node[item.node_id][#by_node[item.node_id] + 1] = item.value
	end
	for _, result in ipairs(results) do result.codes = by_node[result.id] or result.codes or {} end
	c:commit(PW)
	c:commit(CFG)
	return {ok=true, imported=#results, codes_created=#created + #explicit_created, extracted=#links, ignored=#ignored, nodes=results, warnings=ignored}
end

local function ip_to_mac(ip)
	if not tostring(ip):match("^%d+%.%d+%.%d+%.%d+$") then return nil end
	sys.call("ping -c 1 -W 1 " .. shellquote(ip) .. " >/dev/null 2>&1")
	local out = sys.exec("ip neigh show " .. shellquote(ip) .. " 2>/dev/null") or ""
	return out:match("lladdr%s+([%x:]+)")
end

local function hostname_for(c, mac, ip)
	local leases = read_file("/tmp/dhcp.leases") or ""
	for line in leases:gmatch("[^\n]+") do
		local _, lm, lip, host = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
		if lm and ((mac and lm:lower() == mac:lower()) or lip == ip) then return host ~= "*" and host or "未知设备" end
	end
	return "未知设备"
end

local function managed_acls_for_binding(c, binding)
	local out = {}
	if not binding then return out end
	local marker = binding[".name"] or ""
	local mac = (binding.mac or ""):lower()
	c:foreach(PW, "acl_rule", function(s)
		local raw_sources = s.sources or ""
		if type(raw_sources) == "table" then raw_sources = table.concat(raw_sources, " ") end
		local sources = " " .. tostring(raw_sources):lower() .. " "
		local source_match = mac ~= "" and sources:find(" " .. mac .. " ", 1, true) ~= nil
		local legacy_match = source_match and (s.remarks or ""):match("^PWC ") ~= nil
		if s.pwc_binding_id == marker or s[".name"] == binding.acl_id or legacy_match then
			out[#out + 1] = s
		end
	end)
	return out
end

local function remove_binding(c, binding)
	if not binding then return end
	for _, acl in ipairs(managed_acls_for_binding(c, binding)) do c:delete(PW, acl[".name"]) end
	if binding.mac then
		local mac_key = binding.mac:gsub(":", ""):lower()
		c:delete("dhcp", "pwc_" .. mac_key)
		os.remove("/tmp/passwall-device-offline/" .. mac_key)
	end
	c:delete(CFG, binding[".name"])
end

local function copy_acl_options(c, source, target)
	for key, value in pairs(source or {}) do
		if key:sub(1, 1) ~= "." then
			if type(value) == "table" then
				c:delete(PW, target, key)
				for _, item in ipairs(value) do c:add_list(PW, target, key, item) end
			else
				c:set(PW, target, key, value)
			end
		end
	end
end

local function dhcp_host_matches_mac(section, target_mac)
	local value = section and section.mac or ""
	if type(value) == "table" then
		for _, item in ipairs(value) do
			if tostring(item):lower() == target_mac then return true end
		end
		return false
	end
	for item in tostring(value):gmatch("[^%s,]+") do
		if item:lower() == target_mac then return true end
	end
	return false
end

local function ensure_dhcp(c, mac, ip, hostname)
	local target_mac = tostring(mac or ""):lower()
	local id = "pwc_" .. target_mac:gsub(":", "")
	local matches, preferred = {}, nil
	c:foreach("dhcp", "host", function(section)
		if dhcp_host_matches_mac(section, target_mac) then
			matches[#matches + 1] = section[".name"]
			if not tostring(section[".name"]):match("^pwc_") then preferred = section[".name"] end
		end
	end)
	if preferred then
		for _, name in ipairs(matches) do
			if name ~= preferred and tostring(name):match("^pwc_") then c:delete("dhcp", name) end
		end
		return preferred, false
	end
	if #matches > 0 then return matches[1], false end
	local ip_conflict = false
	c:foreach("dhcp", "host", function(section)
		if tostring(section.ip or "") == tostring(ip or "") then ip_conflict = true end
	end)
	if ip_conflict then return nil, false, "ip_conflict" end
	c:set("dhcp", id, "host")
	c:set("dhcp", id, "name", hostname ~= "未知设备" and hostname or id)
	c:set("dhcp", id, "mac", mac)
	c:set("dhcp", id, "ip", ip)
	return id, true
end

local function migrate_codes(c)
	local created, assigned = 0, 0
	local metas = {}
	c:foreach(CFG, "node", function(s) metas[#metas + 1] = s end)
	for _, meta in ipairs(metas) do
		local existing = codes_for_node(c, meta.passwall_id)
		local legacy = trim(meta.code)
		if #existing == 0 and legacy ~= "" then
			new_section(c, CFG, "code", "pwc_code_", {
				node_id=meta.passwall_id, value=legacy, created_at=meta.created_at or os.date("%Y-%m-%d %H:%M:%S")
			})
			created = created + 1
		end
		if legacy ~= "" then c:delete(CFG, meta[".name"], "code") end
	end
	local used = {}
	local bindings = {}
	c:foreach(CFG, "binding", function(s) bindings[#bindings + 1] = s end)
	table.sort(bindings, function(a, b) return (a.bound_at or "") > (b.bound_at or "") end)
	for _, binding in ipairs(bindings) do
		local code_id = binding.code_id
		if not valid_id(code_id or "") or not c:get(CFG, code_id, "value") or used[code_id] then code_id = nil end
		if not code_id then
			for _, code in ipairs(codes_for_node(c, binding.node_id)) do
				if not used[code[".name"]] then code_id = code[".name"]; break end
			end
			if not code_id then
				local prefix = c:get(CFG, "global", "code_prefix") or ""
				local width = tonumber((c:get(CFG, "global", "code_width"))) or 3
				local next_number = tonumber((c:get(CFG, "global", "next_code_number"))) or 1
				local generated = create_codes(c, {binding.node_id}, prefix, next_number, width, 1)
				code_id = generated[1].id
				created = created + 1
			end
			c:set(CFG, binding[".name"], "code_id", code_id)
			c:set(CFG, binding[".name"], "code", c:get(CFG, code_id, "value") or "")
			assigned = assigned + 1
		end
		used[code_id] = true
	end
	c:set(CFG, "global", "offline_unbind_seconds", "0")
	sys.call("rm -rf /tmp/passwall-device-offline")
	return created, assigned
end

local function migrate_acls()
	local c = uci.cursor()
	local codes_created, codes_assigned = migrate_codes(c)
	local bindings = {}
	c:foreach(CFG, "binding", function(s) bindings[#bindings + 1] = s end)
	local migrated, cores_migrated, dhcp_reused = 0, 0, 0
	local has_sing_box = sys.call("test -x /usr/bin/sing-box") == 0
	c:foreach(CFG, "node", function(meta)
		local node_id = meta.passwall_id or ""
		if has_sing_box and c:get(PW, node_id, "protocol") == "socks" and c:get(PW, node_id, "type") ~= "sing-box" then
			c:set(PW, node_id, "type", "sing-box")
			cores_migrated = cores_migrated + 1
		end
	end)
	for _, binding in ipairs(bindings) do
		if (binding.wireless or "") == "" then c:set(CFG, binding[".name"], "wireless", "1") end
		local matches = managed_acls_for_binding(c, binding)
		local acl = matches[1]
		if acl then
			if not acl[".anonymous"] then
				local old_name = acl[".name"]
				local new_name = c:add(PW, "acl_rule")
				copy_acl_options(c, acl, new_name)
				c:delete(PW, old_name)
				acl = c:get_all(PW, new_name)
				migrated = migrated + 1
			end
			c:set(PW, acl[".name"], "pwc_managed", "1")
			c:set(PW, acl[".name"], "pwc_binding_id", binding[".name"])
			c:set(CFG, binding[".name"], "acl_id", acl[".name"])
		end
		local _, created = ensure_dhcp(c, binding.mac or "", binding.ip or "", binding.hostname or "未知设备")
		if not created then dhcp_reused = dhcp_reused + 1 end
	end
	c:set(PW, "@global[0]", "client_proxy", "0")
	c:commit(PW)
	c:commit(CFG)
	c:commit("dhcp")
	return {ok=true, migrated=migrated, cores_migrated=cores_migrated, dhcp_reused=dhcp_reused,
		bindings=#bindings, codes_created=codes_created, codes_assigned=codes_assigned}
end

local function prune_offline()
	local c = uci.cursor()
	if c:get(CFG, "global", "enabled") ~= "1" then return {ok=true, removed=0, disabled=true} end
	local timeout = tonumber((c:get(CFG, "global", "offline_unbind_seconds"))) or 60
	if timeout <= 0 then
		sys.call("rm -rf /tmp/passwall-device-offline")
		return {ok=true, removed=0, disabled=true}
	end
	timeout = math.max(15, math.min(86400, timeout))
	local wireless, scanned = wifi_clients()
	if not scanned then return {ok=false, removed=0, error="无法读取无线客户端状态"} end
	sys.call("mkdir -p /tmp/passwall-device-offline")
	local now = os.time()
	local remove = {}
	local changed = false
	c:foreach(CFG, "binding", function(binding)
		local mac = (binding.mac or ""):lower()
		local timer = "/tmp/passwall-device-offline/" .. mac:gsub(":", "")
		if wireless[mac] then
			os.remove(timer)
			if binding.wireless ~= "1" then c:set(CFG, binding[".name"], "wireless", "1"); changed = true end
		elseif binding.wireless == "1" then
			local first_missing = tonumber(trim(read_file(timer) or ""))
			if not first_missing then
				local f = io.open(timer, "w")
				if f then f:write(tostring(now)); f:close() end
			elseif now - first_missing >= timeout then
				remove[#remove + 1] = binding
			end
		end
	end)
	for _, binding in ipairs(remove) do
		remove_binding(c, binding)
		sys.call("logger -t passwall-device " .. shellquote("无线设备离线自动解绑 mac=" .. (binding.mac or "unknown")))
	end
	if changed or #remove > 0 then c:commit(CFG) end
	if #remove > 0 then
		c:commit(PW)
		c:commit("dhcp")
		sys.call("/usr/share/passwall-device/firewall.sh reload >/dev/null 2>&1 || true")
		sys.call("/etc/init.d/dnsmasq reload >/dev/null 2>&1 || true")
		sys.call("/etc/init.d/passwall restart >/tmp/pwc-auto-unbind.log 2>&1")
		sys.call("/etc/init.d/passwall-device reload >/dev/null 2>&1 || true")
	end
	return {ok=true, removed=#remove, timeout=timeout}
end

local function cleanup_acls()
	local c = uci.cursor()
	local binding_macs = {}
	c:foreach(CFG, "binding", function(s)
		if (s.mac or "") ~= "" then binding_macs[(s.mac or ""):lower()] = true end
	end)
	local remove = {}
	c:foreach(PW, "acl_rule", function(s)
		if s.pwc_managed == "1" or (s.pwc_binding_id or "") ~= "" then
			remove[s[".name"]] = true
			return
		end
		local raw_sources = s.sources or ""
		if type(raw_sources) == "table" then raw_sources = table.concat(raw_sources, " ") end
		if (s.remarks or ""):match("^PWC ") then
			for source in tostring(raw_sources):lower():gmatch("%S+") do
				if binding_macs[source] then remove[s[".name"]] = true end
			end
		end
	end)
	local count = 0
	for name in pairs(remove) do c:delete(PW, name); count = count + 1 end
	c:commit(PW)
	return {ok=true, removed=count}
end

local function rate_state(ip, increment)
	local key=tostring(ip or ""):gsub("[^%w]", "_")
	local path="/tmp/passwall-device-rate-"..key
	local now=os.time(); local count, started=(read_file(path) or ""):match("^(%d+):(%d+)$")
	count=tonumber(count) or 0; started=tonumber(started) or now
	if now-started>=60 then count=0; started=now end
	if increment then count=count+1; local f=io.open(path,"w"); if f then f:write(count,":",started); f:close() end end
	return count>=5 and now-started<60, math.max(0,60-(now-started)), path
end

local function bind(ip, code)
	local c = uci.cursor()
	if c:get(CFG, "global", "enabled") ~= "1" then return {ok=false, error="设备口令服务尚未启用"} end
	local limited, wait_seconds=rate_state(ip, false)
	if limited then return {ok=false,error="失败次数过多，请 "..tostring(wait_seconds).." 秒后重试"} end
	code = trim(code)
	if code == "" then return {ok=false, error="请输入口令"} end
	local code_meta = code_by_value(c, code)
	if not code_meta then
		rate_state(ip, true)
		sys.call("logger -t passwall-device "..shellquote("口令失败 ip="..ip))
		return {ok=false, error="口令无效"}
	end
	local meta = metadata_for_node(c, code_meta.node_id)
	if not meta then return {ok=false, error="口令对应的节点已经不存在"} end
	local nodes = node_map(c)
	if not nodes[meta.passwall_id] then return {ok=false, error="口令对应的节点已经不存在"} end
	local mac = ip_to_mac(ip)
	if not mac then return {ok=false, error="无法识别当前设备，请关闭随机 MAC 后重试"} end
	mac = mac:lower()
	local hostname = hostname_for(c, mac, ip)
	local old_mac = binding_for_mac(c, mac)
	local old_code = binding_for_code(c, code_meta[".name"])
	if old_mac then remove_binding(c, old_mac) end
	if old_code and (not old_mac or old_code[".name"] ~= old_mac[".name"]) then remove_binding(c, old_code) end
	local bid = new_section(c, CFG, "binding", "pwc_bind_", {
		mac=mac, ip=ip, hostname=hostname, node_id=meta.passwall_id, code_id=code_meta[".name"], code=code, acl_id="",
		state="pending", wireless="1", bound_at=os.date("%Y-%m-%d %H:%M:%S")
	})
	local acl = c:add(PW, "acl_rule")
	c:set(PW, acl, "enabled", "1")
	c:set(PW, acl, "remarks", "PWC " .. hostname .. " " .. mac)
	c:set(PW, acl, "sources", mac .. " " .. ip)
	c:set(PW, acl, "pwc_managed", "1")
	c:set(PW, acl, "pwc_binding_id", bid)
	c:set(PW, acl, "tcp_node", meta.passwall_id)
	c:set(PW, acl, "udp_node", "tcp")
	c:set(PW, acl, "tcp_proxy_mode", "proxy")
	c:set(PW, acl, "udp_proxy_mode", "proxy")
	c:set(PW, acl, "filter_proxy_ipv6", "1")
	c:set(PW, acl, "use_global_config", "0")
	c:set(PW, acl, "use_direct_list", "0")
	c:set(PW, acl, "use_proxy_list", "0")
	c:set(PW, acl, "use_block_list", "1")
	c:set(PW, acl, "use_gfw_list", "0")
	c:set(PW, acl, "chn_list", "0")
	c:set(PW, acl, "tcp_redir_ports", "1:65535")
	c:set(PW, acl, "udp_redir_ports", "1:65535")
	c:set(PW, "@global[0]", "enabled", "1")
	c:set(PW, "@global[0]", "acl_enable", "1")
	-- Only per-device ACLs use proxies. Unmatched LAN clients, including wired
	-- computers, remain direct even when a bound node is unavailable.
	c:set(PW, "@global[0]", "client_proxy", "0")
	ensure_dhcp(c, mac, ip, hostname)
	c:set(CFG, bid, "acl_id", acl)
	c:commit(PW); c:commit(CFG); c:commit("dhcp")
	sys.call("/etc/init.d/dnsmasq reload >/dev/null 2>&1")
	sys.call("/usr/share/passwall-device/firewall.sh reload >/dev/null 2>&1 || true")
	local rc = sys.call("/etc/init.d/passwall restart >/tmp/pwc-passwall-apply.log 2>&1")
	if rc ~= 0 then
		local rollback = uci.cursor()
		local b = rollback:get_all(CFG, bid)
		remove_binding(rollback, b)
		rollback:commit(PW); rollback:commit(CFG)
		sys.call("/etc/init.d/passwall restart >/dev/null 2>&1")
		return {ok=false, error="PassWall 应用失败，设备仍保持断网", details=trim(read_file("/tmp/pwc-passwall-apply.log") or "")}
	end
	local active = uci.cursor()
	active:set(CFG, bid, "state", "active")
	active:commit(CFG)
	sys.call("/etc/init.d/passwall-device reload >/dev/null 2>&1")
	local _,_,rate_path=rate_state(ip,false); os.remove(rate_path)
	sys.call("logger -t passwall-device "..shellquote("绑定成功 mac="..mac.." node="..(nodes[meta.passwall_id].remarks or meta.passwall_id)))
	return {ok=true, message="绑定成功", node=nodes[meta.passwall_id].remarks or meta.passwall_id, code=code, kicked=old_code and old_code.mac or nil}
end

local function toggle(enabled)
	local c = uci.cursor()
	enabled = enabled == "1" and "1" or "0"
	c:set(CFG, "global", "enabled", enabled)
	if enabled == "1" then
		c:set(PW, "@global[0]", "acl_enable", "1")
		c:set(PW, "@global[0]", "client_proxy", "0")
	end
	c:commit(CFG); c:commit(PW)
	local rc = sys.call("/etc/init.d/passwall-device " .. (enabled == "1" and "restart" or "stop") .. " >/tmp/pwc-toggle.log 2>&1")
	return rc == 0 and {ok=true, enabled=enabled == "1"} or {ok=false, error=trim(read_file("/tmp/pwc-toggle.log") or "启停失败")}
end

local reload_after_change

local function update_node(node_id, remarks)
	if not valid_id(node_id) then return {ok=false, error="节点标识无效"} end
	remarks = trim(remarks)
	if remarks == "" or #remarks > 128 then return {ok=false, error="节点名称不能为空且不能超过 128 个字符"} end
	local c = uci.cursor()
	local node = c:get_all(PW, node_id)
	local meta = metadata_for_node(c, node_id)
	if not node or node[".type"] ~= "nodes" or not meta then return {ok=false, error="托管节点不存在"} end
	local duplicate_name = false
	c:foreach(CFG, "node", function(s)
		if s[".name"] ~= meta[".name"] and s.remarks == remarks then duplicate_name = true end
	end)
	if duplicate_name then return {ok=false, error="节点名称已存在"} end
	c:set(PW, node_id, "remarks", remarks)
	c:set(CFG, meta[".name"], "remarks", remarks)
	c:commit(PW)
	c:commit(CFG)
	sys.call("logger -t passwall-device " .. shellquote("节点名称已修改 node=" .. node_id))
	return {ok=true, node_id=node_id, remarks=remarks}
end

local function update_code(code_id, value)
	if not valid_id(code_id) then return {ok=false, error="口令标识无效"} end
	value = trim(value)
	if value == "" or #value > 128 then return {ok=false, error="口令不能为空且不能超过 128 个字符"} end
	local c = uci.cursor()
	local code = c:get_all(CFG, code_id)
	if not code or code[".type"] ~= "code" then return {ok=false, error="口令不存在"} end
	local duplicate = code_by_value(c, value)
	if duplicate and duplicate[".name"] ~= code_id then return {ok=false, error="口令已被使用"} end
	c:set(CFG, code_id, "value", value)
	c:foreach(CFG, "binding", function(binding)
		if binding.code_id == code_id then c:set(CFG, binding[".name"], "code", value) end
	end)
	c:commit(CFG)
	return {ok=true, code_id=code_id, value=value}
end

local function add_codes(id_text, count)
	local ids = parse_ids(id_text)
	if not ids or #ids == 0 then return {ok=false, error="请选择有效的节点"} end
	count = math.min(100, math.max(1, tonumber(count) or 1))
	local c = uci.cursor()
	for _, node_id in ipairs(ids) do
		if not metadata_for_node(c, node_id) or not c:get(PW, node_id) then return {ok=false, error="托管节点不存在：" .. node_id} end
	end
	local prefix = c:get(CFG, "global", "code_prefix") or ""
	local width = tonumber((c:get(CFG, "global", "code_width"))) or 3
	local next_number = tonumber((c:get(CFG, "global", "next_code_number"))) or 1
	local created = create_codes(c, ids, prefix, next_number, width, count)
	c:commit(CFG)
	return {ok=true, nodes=#ids, created=#created, codes=created}
end

local function delete_codes(id_text)
	local ids = parse_ids(id_text)
	if not ids or #ids == 0 then return {ok=false, error="请选择有效的口令"} end
	local c, codes, affected = uci.cursor(), {}, {}
	for _, id in ipairs(ids) do
		local code = c:get_all(CFG, id)
		if not code or code[".type"] ~= "code" then return {ok=false, error="口令不存在：" .. id} end
		codes[#codes + 1] = code
		local binding = binding_for_code(c, id)
		if binding then affected[#affected + 1] = binding end
	end
	for _, binding in ipairs(affected) do remove_binding(c, binding) end
	for _, code in ipairs(codes) do c:delete(CFG, code[".name"]) end
	c:commit(PW); c:commit(CFG); c:commit("dhcp")
	local rc = 0
	if #affected > 0 then rc = reload_after_change("/tmp/pwc-delete-code.log") end
	return {ok=rc == 0, deleted=#codes, disconnected=#affected, error=rc ~= 0 and "口令已删除，但 PassWall 重载失败" or nil}
end

local function update_binding(binding_id, remark)
	if not valid_id(binding_id) then return {ok=false, error="绑定标识无效"} end
	remark = trim(remark)
	if #remark > 128 then return {ok=false, error="设备备注不能超过 128 个字符"} end
	local c = uci.cursor()
	local binding = c:get_all(CFG, binding_id)
	if not binding or binding[".type"] ~= "binding" then return {ok=false, error="绑定不存在"} end
	if remark == "" then c:delete(CFG, binding_id, "remark") else c:set(CFG, binding_id, "remark", remark) end
	c:commit(CFG)
	sys.call("logger -t passwall-device " .. shellquote("设备备注已修改 mac=" .. (binding.mac or "unknown")))
	return {ok=true, binding_id=binding_id, remark=remark, hostname=remark ~= "" and remark or (binding.hostname or "未知设备")}
end

reload_after_change = function(log_path)
	sys.call("/etc/init.d/dnsmasq reload >/dev/null 2>&1")
	sys.call("/usr/share/passwall-device/firewall.sh reload >/dev/null 2>&1 || true")
	local rc = sys.call("/etc/init.d/passwall restart >" .. shellquote(log_path or "/tmp/pwc-passwall-apply.log") .. " 2>&1")
	sys.call("/etc/init.d/passwall-device reload >/dev/null 2>&1")
	return rc
end

local function delete_nodes(id_text, replacement)
	local ids = parse_ids(id_text)
	if not ids or #ids == 0 then return {ok=false, error="请选择有效的节点"} end
	local selected = {}
	for _, id in ipairs(ids) do selected[id] = true end
	local c = uci.cursor()
	local nodes, names = {}, {}
	for _, node_id in ipairs(ids) do
		local node = c:get_all(PW, node_id)
		local meta = metadata_for_node(c, node_id)
		if not node or node[".type"] ~= "nodes" or not meta then
			return {ok=false, error="托管节点不存在：" .. node_id}
		end
		nodes[#nodes + 1] = {node=node, meta=meta}
		names[#names + 1] = node.remarks or node_id
	end
	replacement = trim(replacement)
	local target
	if replacement ~= "" then
		target = find_node_by_remark(c, replacement)
		if not target then return {ok=false, error="没有找到替换节点：" .. replacement} end
		if selected[target[".name"]] then return {ok=false, error="替换节点不能同时被选中删除"} end
		if not metadata_for_node(c, target[".name"]) then return {ok=false, error="替换节点不属于本插件管理"} end
	end
	local affected = {}
	c:foreach(CFG, "binding", function(s) if selected[s.node_id or ""] then affected[#affected+1] = s end end)
	local affected_codes = {}
	c:foreach(CFG, "code", function(s) if selected[s.node_id or ""] then affected_codes[#affected_codes + 1] = s end end)
	for _, code in ipairs(affected_codes) do
		if target then c:set(CFG, code[".name"], "node_id", target[".name"])
		else c:delete(CFG, code[".name"])
		end
	end
	for _, b in ipairs(affected) do
		if target then
			c:set(CFG, b[".name"], "node_id", target[".name"])
			c:set(CFG, b[".name"], "state", "pending")
			for _, acl in ipairs(managed_acls_for_binding(c, b)) do
				c:set(PW, acl[".name"], "tcp_node", target[".name"])
				c:set(PW, acl[".name"], "udp_node", "tcp")
			end
		else remove_binding(c, b) end
	end
	for _, item in ipairs(nodes) do
		c:delete(CFG, item.meta[".name"])
		c:delete(PW, item.node[".name"])
	end
	c:commit(PW); c:commit(CFG); c:commit("dhcp")
	local rc = reload_after_change("/tmp/pwc-passwall-apply.log")
	if target and rc == 0 then
		local c2=uci.cursor()
		for _, b in ipairs(affected) do c2:set(CFG, b[".name"], "state", "active") end
		c2:commit(CFG)
	end
	return {ok=rc == 0, deleted=#nodes, deleted_names=names, affected=#affected, moved=target and #affected or 0, replacement=target and target.remarks or nil, error=rc ~= 0 and "节点已删除，但 PassWall 重载失败；相关设备保持断网" or nil}
end

local function unbind_many(id_text)
	local ids = parse_ids(id_text)
	if not ids or #ids == 0 then return {ok=false,error="请选择有效的设备"} end
	local c, bindings = uci.cursor(), {}
	for _, id in ipairs(ids) do
		local binding = c:get_all(CFG, id)
		if not binding or binding[".type"] ~= "binding" then return {ok=false,error="绑定不存在：" .. id} end
		bindings[#bindings + 1] = binding
	end
	for _, binding in ipairs(bindings) do remove_binding(c, binding) end
	c:commit(PW); c:commit(CFG); c:commit("dhcp")
	local rc = reload_after_change("/tmp/pwc-unbind.log")
	return {ok=rc == 0, removed=#bindings, error=rc ~= 0 and "设备已解绑，但 PassWall 重载失败" or nil}
end

-- 一键恢复初始配置：清空全部节点、口令、设备绑定与相关规则，
-- 停用认证服务，并把 PassWall 恢复到安装前快照状态。
local function reset_all()
	local c = uci.cursor()
	local bindings, codes, metas = {}, {}, {}
	c:foreach(CFG, "binding", function(s) bindings[#bindings + 1] = s end)
	c:foreach(CFG, "code", function(s) codes[#codes + 1] = s end)
	c:foreach(CFG, "node", function(s) metas[#metas + 1] = s end)
	local deleted_nodes = {}
	for _, binding in ipairs(bindings) do remove_binding(c, binding) end
	for _, code in ipairs(codes) do c:delete(CFG, code[".name"]) end
	for _, meta in ipairs(metas) do
		local node_id = meta.passwall_id or ""
		if node_id ~= "" and c:get(PW, node_id) then
			c:delete(PW, node_id)
			deleted_nodes[#deleted_nodes + 1] = node_id
		end
		c:delete(CFG, meta[".name"])
	end
	local acls = {}
	c:foreach(PW, "acl_rule", function(s)
		if s.pwc_managed == "1" or (s.pwc_binding_id or "") ~= "" or (s.remarks or ""):match("^PWC ") then
			acls[#acls + 1] = s[".name"]
		end
	end)
	for _, name in ipairs(acls) do c:delete(PW, name) end
	-- 全局配置恢复默认
	c:set(CFG, "global", "enabled", "0")
	c:set(CFG, "global", "code_start", "1")
	c:set(CFG, "global", "code_width", "3")
	c:delete(CFG, "global", "code_prefix")
	c:delete(CFG, "global", "next_code_number")
	c:delete(CFG, "global", "admin_macs")
	c:commit(PW); c:commit(CFG); c:commit("dhcp")
	-- 停用认证服务并恢复 PassWall 安装前快照
	sys.call("/etc/init.d/passwall-device stop >/dev/null 2>&1 || true")
	local previous_enabled = c:get(CFG, "global", "previous_passwall_enabled")
	local previous_acl = c:get(CFG, "global", "previous_acl_enable")
	if previous_enabled ~= nil then c:set(PW, "@global[0]", "enabled", previous_enabled) end
	if previous_acl ~= nil then c:set(PW, "@global[0]", "acl_enable", previous_acl) end
	c:commit(PW)
	sys.call("/etc/init.d/passwall restart >/dev/null 2>&1 || true")
	sys.call("/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true")
	sys.call("logger -t passwall-device " .. shellquote("已恢复初始配置：删除节点 " .. #deleted_nodes .. " 个、口令 " .. #codes .. " 个、绑定 " .. #bindings .. " 台"))
	return {ok=true, message="已恢复初始配置，所有节点、口令和设备绑定已清空，认证服务已停用",
		deleted_nodes=#deleted_nodes, deleted_codes=#codes, deleted_bindings=#bindings}
end

local function record_node_test(node_id, result)
	local c = uci.cursor()
	local meta = metadata_for_node(c, node_id)
	if meta then
		c:set(CFG, meta[".name"], "last_test_at", os.date("%Y-%m-%d %H:%M:%S"))
		c:set(CFG, meta[".name"], "last_reachable", result.reachable and "1" or "0")
		if trim(result.exit_ip) ~= "" then c:set(CFG, meta[".name"], "last_exit_ip", result.exit_ip)
		else c:delete(CFG, meta[".name"], "last_exit_ip") end
		c:set(CFG, meta[".name"], "last_test_message", result.message or result.error or "")
		c:commit(CFG)
	end
	return result
end

local function test_node(node_id)
	if not valid_id(node_id) then return {ok=false,error="节点标识无效"} end
	local c=uci.cursor(); local n=c:get_all(PW,node_id)
	if not n or n[".type"]~="nodes" then return {ok=false,error="节点不存在"} end
	local pid=nixio.getpid(); local port=30000+(pid%10000)
	local name="pwc-node-test-"..tostring(pid)..".json"
	local config="/tmp/etc/passwall/"..name
	local log="/tmp/pwc-node-test-"..tostring(pid)..".log"
	local output="/tmp/pwc-node-test-"..tostring(pid)..".out"
	local pidfile="/tmp/pwc-node-test-"..tostring(pid)..".pid"
	sys.call("mkdir -p /tmp/etc/passwall")
	sys.call("/usr/share/passwall/app.sh run_socks flag=pwc_node_test node="..shellquote(node_id).." bind=127.0.0.1 socks_port="..tostring(port).." config_file="..shellquote(name).." no_run=1 >/dev/null 2>&1 || true")
	if not read_file(config) then return record_node_test(node_id, {ok=false,reachable=false,error="PassWall 无法生成该节点的测试配置"}) end
	local node_type=(n.type or "Xray"):lower()
	local binary, args="/usr/bin/xray", "run -config"
	if node_type=="sing-box" then binary="/usr/bin/sing-box"; args="run -c" end
	if sys.call("test -x "..shellquote(binary))~=0 then os.remove(config); return record_node_test(node_id, {ok=false,reachable=false,error="缺少节点所需代理核心"}) end
	local started=os.time()
	sys.call("("..shellquote(binary).." "..args.." "..shellquote(config).." >"..shellquote(log).." 2>&1 & echo $! >"..shellquote(pidfile)..")")
	sys.call("sleep 1")
	local rc=sys.call("curl --proxy socks5h://127.0.0.1:"..tostring(port).." --connect-timeout 3 --max-time 8 -fsS https://api.ipify.org -o "..shellquote(output).." 2>/dev/null")
	local child=trim(read_file(pidfile) or "")
	if child:match("^%d+$") then sys.call("kill "..child.." >/dev/null 2>&1 || true") end
	local exit_ip=trim(read_file(output) or "")
	local details=trim(read_file(log) or "")
	os.remove(config); os.remove(log); os.remove(output); os.remove(pidfile)
	if rc==0 and exit_ip~="" then return record_node_test(node_id, {ok=true,reachable=true,exit_ip=exit_ip,elapsed_seconds=os.time()-started,message="代理可用，出口 IP："..exit_ip}) end
	return record_node_test(node_id, {ok=false,reachable=false,error="代理测试失败，节点将保持断网",details=details})
end

local UPDATE_MANIFESTS = {
	"https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/update.json",
	"http://m.yaml.uk:25532/update.json"
}

local function version_parts(version)
	local parts = {}
	for number in tostring(version or ""):gmatch("%d+") do parts[#parts + 1] = tonumber(number) or 0 end
	return parts
end

local function version_newer(remote, current)
	local a, b = version_parts(remote), version_parts(current)
	for i = 1, math.max(#a, #b) do
		local av, bv = a[i] or 0, b[i] or 0
		if av ~= bv then return av > bv end
	end
	return false
end

local function parse_manifest(manifest)
	if type(manifest) ~= "table" then return nil end
	if not (tostring(manifest.version or ""):match("^%d+[%d%.%-]*$") and
	   tostring(manifest.ipk_url or ""):match("^https?://[%w%._~:/%?#%[%]@!$&'()*+,;=%%%-]+$") and
	   tostring(manifest.sha256 or ""):match("^[a-fA-F0-9]+$") and #tostring(manifest.sha256) == 64) then
		return nil
	end
	local history, seen = {}, {}
	if type(manifest.history) == "table" then
		for _, item in ipairs(manifest.history) do
			if type(item) == "table" and tostring(item.version or ""):match("^%d+[%d%.%-]*$") and
			   tostring(item.ipk_url or ""):match("^https?://[%w%._~:/%?#%[%]@!$&'()*+,;=%%%-]+$") and
			   tostring(item.sha256 or ""):match("^[a-fA-F0-9]+$") and #tostring(item.sha256) == 64 and
			   not seen[item.version] then
				seen[item.version] = true
				history[#history + 1] = {
					version=item.version, ipk_url=item.ipk_url,
					sha256=item.sha256:lower(), notes=tostring(item.notes or "")
				}
			end
		end
	end
	table.sort(history, function(a, b) return version_newer(a.version, b.version) end)
	return {
		version=manifest.version, ipk_url=manifest.ipk_url, sha256=manifest.sha256:lower(),
		notes=manifest.notes or "", published_at=manifest.published_at or "", history=history
	}
end

local function fetch_update_manifest()
	local path = "/tmp/passwall-device-update-" .. tostring(nixio.getpid()) .. ".json"
	for _, url in ipairs(UPDATE_MANIFESTS) do
		os.remove(path)
		local rc = sys.call("curl -4 -fsSL --connect-timeout 5 --max-time 12 " .. shellquote(url) .. " -o " .. shellquote(path) .. " 2>/dev/null")
		if rc == 0 then
			local manifest = parse_manifest(jsonc.parse(read_file(path) or ""))
			os.remove(path)
			if manifest then
				manifest.source = url
				return manifest
			end
		else
			os.remove(path)
		end
	end
	return nil, "无法获取更新信息，请检查路由器网络或稍后重试"
end

local function check_update()
	local current = trim(read_file("/usr/share/passwall-device/VERSION") or "0.0.0")
	local manifest, err = fetch_update_manifest()
	if not manifest then return {ok=false, current=current, error=err} end
	return {
		ok=true, current=current, latest=manifest.version,
		available=version_newer(manifest.version, current),
		notes=manifest.notes or "", published_at=manifest.published_at or "", source=manifest.source,
		history=manifest.history or {}
	}
end

-- 下载、校验 SHA-256 并 opkg 安装指定包；成功返回 nil，失败返回错误信息与详情
local function install_package(ipk_url, expected_sha256, log_path, extra_flags)
	local ipk = "/tmp/passwall-device-update-" .. tostring(nixio.getpid()) .. ".ipk"
	os.remove(ipk)
	local rc = sys.call("curl -4 -fsSL --connect-timeout 8 --max-time 120 " .. shellquote(ipk_url) .. " -o " .. shellquote(ipk) .. " 2>" .. shellquote(log_path))
	if rc ~= 0 then os.remove(ipk); return "更新包下载失败", trim(read_file(log_path) or "") end
	local actual = trim(sys.exec("sha256sum " .. shellquote(ipk) .. " 2>/dev/null | cut -d' ' -f1") or ""):lower()
	if actual ~= expected_sha256:lower() then
		os.remove(ipk)
		return "更新包校验失败，已拒绝安装", ""
	end
	rc = sys.call("opkg install " .. (extra_flags or "") .. " " .. shellquote(ipk) .. " >" .. shellquote(log_path) .. " 2>&1")
	os.remove(ipk)
	if rc ~= 0 then return "更新安装失败", trim(read_file(log_path) or "") end
	return nil
end

local function install_update()
	local current = trim(read_file("/usr/share/passwall-device/VERSION") or "0.0.0")
	local manifest, err = fetch_update_manifest()
	if not manifest then return {ok=false, current=current, error=err} end
	if not version_newer(manifest.version, current) then
		return {ok=false, current=current, latest=manifest.version, error="当前已经是最新版本"}
	end
	local install_error, details = install_package(manifest.ipk_url, manifest.sha256, "/tmp/passwall-device-update.log")
	if install_error then
		return {ok=false, current=current, latest=manifest.version, error=install_error, details=details}
	end
	local installed = trim(read_file("/usr/share/passwall-device/VERSION") or current)
	return {ok=true, previous=current, version=installed, message="更新完成，页面即将刷新"}
end

local function rollback(version)
	version = trim(version)
	local current = trim(read_file("/usr/share/passwall-device/VERSION") or "0.0.0")
	if version == "" then return {ok=false, current=current, error="请选择要回退的版本"} end
	if version == current then return {ok=false, current=current, error="该版本就是当前版本，无需回退"} end
	local manifest, err = fetch_update_manifest()
	if not manifest then return {ok=false, current=current, error=err} end
	local target
	for _, item in ipairs(manifest.history or {}) do
		if item.version == version then target = item; break end
	end
	if not target then
		return {ok=false, current=current, latest=manifest.version, error="更新清单中没有版本 " .. version .. " 的回退包"}
	end
	local install_error, details = install_package(target.ipk_url, target.sha256, "/tmp/passwall-device-rollback.log", "--force-downgrade")
	if install_error then
		return {ok=false, current=current, version=version, error=install_error, details=details}
	end
	local installed = trim(read_file("/usr/share/passwall-device/VERSION") or current)
	return {ok=true, previous=current, version=installed, message="已回退到 " .. installed .. "，页面即将刷新"}
end

local action=arg[1] or "status"
if action=="status" then reply(list_status())
elseif action=="extract" then local links, ignored=extract_links(read_file(arg[2]) or ""); reply({ok=true,links=links,ignored=ignored})
elseif action=="import" then reply(import_nodes(arg[2],arg[3],arg[4],arg[5],arg[6],arg[7],arg[8]))
elseif action=="bind" then reply(bind(arg[2] or "",arg[3] or ""))
elseif action=="toggle" then reply(toggle(arg[2]))
elseif action=="delete-node" then reply(delete_nodes(arg[2] or "",arg[3] or ""))
elseif action=="delete-nodes" then reply(delete_nodes(arg[2] or "",arg[3] or ""))
elseif action=="unbind" then reply(unbind_many(arg[2] or ""))
elseif action=="unbind-many" then reply(unbind_many(arg[2] or ""))
elseif action=="test-node" then reply(test_node(arg[2] or ""))
elseif action=="update-node" then reply(update_node(arg[2] or "",arg[3] or ""))
elseif action=="update-code" then reply(update_code(arg[2] or "",arg[3] or ""))
elseif action=="add-codes" then reply(add_codes(arg[2] or "",arg[3] or "1"))
elseif action=="delete-codes" then reply(delete_codes(arg[2] or ""))
elseif action=="update-binding" then reply(update_binding(arg[2] or "",arg[3] or ""))
elseif action=="check-update" then reply(check_update())
elseif action=="install-update" then reply(install_update())
elseif action=="rollback" then reply(rollback(arg[2] or ""))
elseif action=="reset" then reply(reset_all())
elseif action=="wifi-macs" then reply(wifi_mac_list())
elseif action=="migrate" then reply(migrate_acls())
elseif action=="prune-offline" then reply(prune_offline())
elseif action=="cleanup-acls" then reply(cleanup_acls())
else reply({ok=false,error="未知操作"}) end
