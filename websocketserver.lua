local skynet = require "skynet"
local socket = require "socket"
local string = require "string"
local websocket = require "websocket"
local httpd = require "http.httpd"
local urllib = require "http.url"
local sockethelper = require "http.sockethelper"
-- local snax = require "snax"
-- local mSnaxRoomManager

local handler = {}

local CMD = {}
local WEB_CMD = {}

local mWebFd = {}

local watchdog

local connection = {}
local forwarding = {}

local client_number = 0

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
}

function WEB_CMD.open(vFd, vToken, vFrom)
    
end

function handler.on_open(ws, conf)
    local nfd = conf.id or 0
    local naddr = conf.addr 
    print(string.format("%d::open", ws.id))
    local c = {
        fd = nfd,
        ip = naddr,
    }
    connection[nfd] = c
    skynet.send(watchdog, "lua", "socket", "open", nfd, naddr)
end

function handler.on_message(ws, message)
   
    local c = connection[ws.id]
    local agent = c.agent
    if agent then
        skynet.redirect(agent, c.client, "client", 1, message)
    else
        -- skynet.send(watchdog, "lua", "socket", "data", fd, netpack.tostring(msg, sz))
    end
    
end

function handler.on_close(ws, code, reason)
    close_fd(ws.id)
    skynet.send(watchdog, "lua", "socket", "close", ws.id)
end

function close_fd(fd)
    local c = connection[fd]
    if c then
        unforward(c)
        connection[fd] = nil
    end
end


local function handle_socket(id,addr)
    -- limit request body size to 8192 (you can pass nil to unlimit)
    local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
    if code then
        local conf = {}
        conf.id = id
        conf.addr = addr
        local ws = websocket.new(id, header, handler, conf)

        mWebFd[id] = ws
        ws:start()
    end


end

function CMD.open(conf)
    watchdog = conf.watchdog
    local address1 = conf.address or "0.0.0.0"
    local port = assert(conf.port)
    local address = address1..":"..port
    skynet.error("Listening "..address)
    local id = assert(socket.listen(address))
    socket.start(id , function(id, addr)
       socket.start(id)
       pcall(handle_socket, id,addr)
    end)

end

-- 关闭watchdog
function CMD.kick(fd)
    local nConn = mWebFd[fd]
    if nConn then
        mWebFd[fd] = false
        nConn:close()
    end
end

function CMD.forward(fd, agent)
    if mWebFd[fd] then
    end
    forwards(fd, agent)
    local nConn = assert(mWebFd[fd])
    nConn:unforward()
    nConn:forward(agent,fd)
    
end

function forwards(fd, agent, client)
    local c = assert(connection[fd])
    unforward(c)
    c.client = client or 0
    c.agent = agent
    forwarding[c.agent] = c
end

function unforward(c)
    if c.agent then
        forwarding[c.agent] = nil
        c.agent = nil
        c.client = nil
    end
end

function WEB_CMD.send(vFd, vData)
    local nConn = mWebFd[vFd]
    if nConn then
        nConn:send_binary(vData)
    else
        skynet.error("websocket connection not found for fd=", vFd)
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        if cmd=="websocket" then
            local f = assert(WEB_CMD[subcmd])
            f(...)
            -- udp cmd not need ret
            -- skynet.ret(skynet.pack(f(...)))
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
end)
