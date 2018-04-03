local skynet = require "skynet"
local netpack = require "netpack"

local CMD = {}
local SOCKET = {}
local websocketserver	= nil		-- gate
local agent = {}
local agentNum = 0

function SOCKET.open(fd, addr)
	skynet.error("New websocket client from==== : " .. addr)
	agent[fd] = skynet.newservice("agent")
	skynet.call(agent[fd], "lua", "start", { gate = websocketserver, client = fd, watchdog = skynet.self(), use_websocket=true, addr = addr})
end

local function close_agent(fd)
	local a = agent[fd]
	agent[fd] = nil
	if a then
		skynet.call(websocketserver, "lua", "kick", fd)
		-- disconnect never return
		skynet.send(a, "lua", "disconnect",agentNum)
	end
end

function SOCKET.close(fd)
	close_agent(fd)
end

function SOCKET.data(fd, msg)
end

function CMD.start(conf)
	local conf = conf or {}
	conf.watchdog = skynet.self()
	skynet.call(websocketserver, "lua", "open" , conf)
end

function CMD.close(fd)
	close_agent(fd)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	websocketserver = skynet.newservice("websocketserver")
	
end)
