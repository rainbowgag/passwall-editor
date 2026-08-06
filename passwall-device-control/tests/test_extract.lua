local sample = [[
这里是节点说明
vless://uuid@example.com:443?security=tls#node-a
vmess://eyJ2IjoiMiJ9
trojan-go://password@example.net:443/?type=ws&path=%2fws&#trojan-go
trojan://secret@example.org:443?security=tls&sni=example.org&type=tcp#trojan
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@example.net:8388#shadowsocks
socks://dXNlcjpwYXNz@example.org:1080#base64-auth
192.0.2.10:1080:user:pass
socks5://u:p@198.51.100.2:1080#socks
无关内容
]]

local path = "/tmp/pwc-extract-fixture.txt"
local f = assert(io.open(path, "w")); f:write(sample); f:close()
local pipe = assert(io.popen("lua ./root/usr/share/passwall-device/app.lua extract " .. path))
local result = pipe:read("*a"); pipe:close(); os.remove(path)
local parsed = assert(require("luci.jsonc").parse(result), result)
assert(parsed.ok == true, result)
assert(#parsed.links == 8, result)
assert(parsed.links[1]:find("vless://uuid@example.com:443", 1, true), result)
assert(parsed.links[3]:find("trojan-go://password@example.net:443", 1, true), result)
assert(parsed.links[4]:find("trojan://secret@example.org:443", 1, true), result)
assert(parsed.links[5]:find("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@example.net:8388", 1, true), result)
assert(parsed.links[6]:find("socks://dXNlcjpwYXNz@example.org:1080", 1, true), result)
assert(parsed.links[7] == "socks5://user:pass@192.0.2.10:1080", result)
assert(#parsed.ignored == 2, result)
print("extract tests passed")
