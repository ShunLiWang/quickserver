--[[

Copyright (c) 2011-2015 chukong-inc.com

https://github.com/dualface/quickserver

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

]]

local ServerAppBase = import(".ServerAppBase")

local WebSocketsServerBase = class("WebSocketsServerBase", ServerAppBase)

WebSocketsServerBase.WEBSOCKETS_READY_EVENT = "WEBSOCKETS_READY_EVENT"
WebSocketsServerBase.WEBSOCKETS_CLOSE_EVENT = "WEBSOCKETS_CLOSE_EVENT"

function WebSocketsServerBase:ctor(config)
    WebSocketsServerBase.super.ctor(self, config)

    self.requestType = "websockets"
    self.config.websocketsTimeout = self.config.websocketsTimeout or 10 * 1000
    self.config.websocketsMaxPayloadLen = self.config.websocketsMaxPayloadLen or 16 * 1024
    self.config.websocketsMessageFormat = self.config.websocketsMessageFormat or "json"

    local ok, err = ngx.on_abort(function()
        self:dispatchEvent({name = ServerAppBase.CLIENT_ABORT_EVENT})
    end)
    if not ok then
        printInfo("failed to register the on_abort callback, ", err)
    end
end

function WebSocketsServerBase:closeClientConnect()
    if self.websockets then
        self.websockets:send_close()
        self.websockets = nil
    end
end

function WebSocketsServerBase:runEventLoop()
    local server = require("resty.websocket.server")
    local wb, err = server:new({
        timeout = self.config.websocketsTimeout,
        max_payload_len = self.config.websocketsMaxPayloadLen,
    })

    if not wb then
        printInfo("failed to new websocket: ".. err)
        return ngx.HTTP_SERVICE_UNAVAILABLE
    end

    self.websockets = wb
    self:dispatchEvent({name = WebSocketsServerBase.WEBSOCKETS_READY_EVENT})

    local ret = ngx.OK
    local againCount = 0
    local maxAgainCount = self.config.maxWebsocketRetryCount
    -- event loop
    while true do
        local data, typ, err = wb:recv_frame()
        if wb.fatal then
            printInfo("failed to receive frame, %s", err)
            if err == "again" and againCount < maxAgainCount then
                againCount = againCount + 1
                goto recv_next_message
            end
            ret = 444
            break
        end

        if not data then
            -- timeout, send ping
            local bytes, err = wb:send_ping()
            if not bytes and self.config.debug then
                printInfo("failed to send ping, %s", err)
            end
        elseif typ == "close" then
            break -- exit event loop
        elseif typ == "ping" then
            -- send pong
            local bytes, err = wb:send_pong()
            if not bytes and self.config.debug then
                printInfo("failed to send pong, %s", err)
            end
        elseif typ == "pong" then
            -- ngx.log(ngx.ERR, "client ponged")
        elseif typ == "text" then
            local ok, err = self:processWebSocketsMessage(data, typ)
            if not ok then
                printInfo("process text message failed: %s", err)
            end
        elseif typ == "binary" then
            local ok, err = self:processWebSocketsMessage(data, typ)
            if not ok then
                printInfo("process binary message failed: %s", err)
            end
        else
            printInfo("unknwon typ %s", tostring(typ))
        end

::recv_next_message::

    end -- while

    self:dispatchEvent({name = WebSocketsServerBase.WEBSOCKETS_CLOSE_EVENT})
    wb:send_close()
    self.websockets = nil

    return ret
end

function WebSocketsServerBase:processWebSocketsMessage(rawMessage, messageType)
    if messageType ~= "text" then
        return false, string.format("not supported message type %s", messageType)
    end

    local ok, message = self:parseWebSocketsMessage(rawMessage)
    if not ok then
        return false, message
    end

    local msgid = message.msg_id
    local actionName = message.action

    local result = self:doRequest(actionName, message)
    if type(result) == "table" then
        if msgid then
            result.msg_id = msgid
        else
            if self.config.debug then
                printInfo("unused result from action %s", actionName)
            end
            result = nil
        end
    elseif result ~= nil then
        if msgid then
            printInfo("invalid result from action %s for message %s", actionName, msgid)
            result = {error = result}
        else
            printInfo("invalid result from action %s", actionName)
            result = nil
        end
    end

    if not self.websockets then
        return false, "websockets removed"
    end

    if result then
        local bytes, err = self.websockets:send_text(json.encode(result))
        if not bytes then
            return false, err
        end
    end

    return true
end

function WebSocketsServerBase:parseWebSocketsMessage(rawMessage)
    if self.config.websocketsMessageFormat == "json" then
        local message = json.decode(rawMessage)
        if type(message) == "table" then
            return true, message
        else
            return false, string.format("invalid message format %s", tostring(rawMessage))
        end
    else
        return false, string.format("not support message format %s", tostring(self.config.websocketsMessageFormat))
    end
end

return WebSocketsServerBase
