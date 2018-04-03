require "functions"
require "const"

local skynet = require "skynet"
local agentSkynet = require "skynet"
local socket = require "socket"
local sprotoloader = require "sprotoloader"
local snax = require "snax"
local cjson = require "cjson"
local mc = require "multicast"
local dc = require "datacenter"
-- local profile = require "profile"

local WATCHDOG
local host
local sender

local CMD = {}
local REQUEST = {}
local client_fd
local hearbeat = 0
local tempHearbeat = 0
local addr = ""
local environment = 1

local USE_TCP = 1
local USE_KCP = 2
local USE_WEBSOCKET = 3
local use_socket

-- 设置resData
local function setResData(vErrCode, vParam1, vParam2)
	local nData = { resData = { errCode = vErrCode, errParam1 = vParam1, errParam2 = vParam2 } }
	return nData
end

-- 获取返回消息体
local function getResData(vResData)
	vResData = vResData or {}
	vResData.serverTime = os.time()
	return vResData
end

local function request(name, args, response)
	local f = assert(REQUEST[name])
	local r = f(args)
	
	if response and r then
		-- 附加消息体
		r.resData = getResData(r.resData)

		return response(r)
	end
end

local function send_package(pack)
	local package = string.pack(">s2", pack)

	if use_socket == USE_KCP then
		skynet.send(udp_server, "lua", "udp", "send", client_fd, package)
	elseif use_socket == USE_WEBSOCKET then
		-- package = string.pack("<s2", pack)
		skynet.send(websocket_server, "lua", "websocket", "send", client_fd, package)
	else
		socket.write(client_fd, package)
	end
	
end

local function sendMsg(msgName, datas, session)
	
	send_package(sender(msgName, datas, session))
end


skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function (_, _, type, ...)
		if type == "REQUEST" then
			local ok, result = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

-- 登陆
function REQUEST:c2sMsgLogin()
	
end

function CMD.start(conf)
	WATCHDOG = conf.watchdog
	
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	sender = host:attach(sprotoloader.load(1))
	client_fd = conf.client
	-- 访问者的IP地址
	if conf.addr then
		local  address, port = string.match(conf.addr, "([^:]+):(.*)$")
		addr = address
	end

	if conf.use_kcp then
		use_socket = USE_KCP
		udp_server = conf.gate

		skynet.call(conf.gate, "lua", "forward", client_fd, skynet.self())
	elseif conf.use_websocket then
		use_socket = USE_WEBSOCKET
		websocket_server = conf.gate
		skynet.call(conf.gate, "lua", "forward", client_fd, skynet.self())
	else
		use_socket = USE_TCP
		skynet.call(conf.gate, "lua", "forward", client_fd)
	end

end

function CMD.disconnect(vAgentNum)
	-- todo: do something before exit 
	skynet.exit()
end

function CMD.sendMsgBattle(vMsgName, vData)
	sendMsg(vMsgName, vData)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		-- 当调用skynet.send的时候 不能ret
		skynet.ret(skynet.pack(f(...)))
	end)
end)
