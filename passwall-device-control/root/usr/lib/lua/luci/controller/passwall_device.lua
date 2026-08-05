module("luci.controller.passwall_device", package.seeall)

local http = require "luci.http"
local sys = require "luci.sys"
local util = require "luci.util"
local jsonc = require "luci.jsonc"
local uci_model = require "luci.model.uci"
local nixio = require "nixio"

local CONFIG = "passwall_device"
local APP = "/usr/share/passwall-device/app.lua"

local function json(data)
	http.prepare_content("application/json")
	http.write(jsonc.stringify(data or {}))
end

local function run(action, args)
	local command = "lua " .. util.shellquote(APP) .. " " .. util.shellquote(action)
	for _, value in ipairs(args or {}) do
		command = command .. " " .. util.shellquote(tostring(value or ""))
	end
	local output = sys.exec(command .. " 2>&1")
	local parsed = jsonc.parse(output or "")
	if parsed then return parsed end
	return { ok = false, error = output ~= "" and output or "后台命令执行失败" }
end

function index()
	if not nixio.fs.access("/etc/config/" .. CONFIG) then return end

	local page = entry({"admin", "services", "passwall_device"}, template("passwall_device/main"), _("PassWall 设备口令"), 3)
	page.dependent = true
	page.acl_depends = { "luci-app-passwall-device" }

	entry({"admin", "services", "passwall_device", "api", "status"}, call("api_status")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "import"}, call("api_import")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "toggle"}, call("api_toggle")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "delete"}, call("api_delete")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "delete-many"}, call("api_delete_many")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "unbind"}, call("api_unbind")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "unbind-many"}, call("api_unbind_many")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "test"}, call("api_test")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "edit"}, call("api_edit")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "edit-code"}, call("api_edit_code")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "add-codes"}, call("api_add_codes")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "delete-codes"}, call("api_delete_codes")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "edit-binding"}, call("api_edit_binding")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "version"}, call("api_version")).leaf = true
	entry({"admin", "services", "passwall_device", "api", "update"}, call("api_update")).leaf = true

	local portal = entry({"pwc"}, template("passwall_device/portal"))
	portal.sysauth = false
	portal.dependent = false
	portal.leaf = false
	local login = entry({"pwc", "login"}, call("portal_login"))
	login.sysauth = false
	login.dependent = false
	login.leaf = true
end

function api_status() json(run("status")) end

function api_import()
	local links = http.formvalue("links") or ""
	local prefix = http.formvalue("prefix") or ""
	local start = http.formvalue("start") or "1"
	local code_prefix = http.formvalue("code_prefix") or ""
	local code_start = http.formvalue("code_start") or "1"
	local code_width = http.formvalue("code_width") or "3"
	local code_count = http.formvalue("code_count") or "1"
	if #links > 524288 then return json({ok=false, error="导入内容不能超过 512KB"}) end
	local path = "/tmp/pwc-import-" .. tostring(nixio.getpid()) .. ".txt"
	local f = io.open(path, "w")
	if not f then return json({ok=false, error="无法创建导入临时文件"}) end
	f:write(links)
	f:close()
	local result = run("import", {path, prefix, start, code_prefix, code_start, code_width, code_count})
	os.remove(path)
	json(result)
end

function api_toggle() json(run("toggle", {http.formvalue("enabled") or "0"})) end
function api_delete() json(run("delete-node", {http.formvalue("node_id") or "", http.formvalue("replacement") or ""})) end
function api_delete_many()
	local ids = http.formvalue("node_ids") or ""
	if #ids > 65535 then return json({ok=false, error="批量节点参数过长"}) end
	json(run("delete-nodes", {ids, http.formvalue("replacement") or ""}))
end
function api_unbind() json(run("unbind", {http.formvalue("binding_id") or ""})) end
function api_unbind_many()
	local ids = http.formvalue("binding_ids") or ""
	if #ids > 65535 then return json({ok=false, error="批量设备参数过长"}) end
	json(run("unbind-many", {ids}))
end
function api_test() json(run("test-node", {http.formvalue("node_id") or ""})) end
function api_edit() json(run("update-node", {http.formvalue("node_id") or "", http.formvalue("remarks") or "", http.formvalue("code") or ""})) end
function api_edit_code() json(run("update-code", {http.formvalue("code_id") or "", http.formvalue("value") or ""})) end
function api_add_codes() json(run("add-codes", {http.formvalue("node_ids") or "", http.formvalue("count") or "1"})) end
function api_delete_codes() json(run("delete-codes", {http.formvalue("code_ids") or ""})) end
function api_edit_binding() json(run("update-binding", {http.formvalue("binding_id") or "", http.formvalue("remark") or ""})) end
function api_version() json(run("check-update")) end
function api_update() json(run("install-update")) end

function portal_login()
	local code = http.formvalue("code") or ""
	if #code > 128 then return json({ok=false, error="口令格式错误"}) end
	local ip = http.getenv("REMOTE_ADDR") or ""
	json(run("bind", {ip, code}))
end
