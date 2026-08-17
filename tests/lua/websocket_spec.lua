local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("WebSocket Module", function()
  local ws_server
  
  -- Setup before tests
  local function setup()
    ws_server = require('consolelog.communication.ws_server')
  end
  
  describe("WebSocket Server", function()
    it("should load ws_server module", function()
      setup()
      assert.not_nil(ws_server, "Should load ws_server module")
      assert.equals(type(ws_server), "table", "Module should be a table")
    end)
    
    it("should have core functions", function()
      setup()
      assert.not_nil(ws_server.start, "Should have start function")
      assert.not_nil(ws_server.stop, "Should have stop function")
      assert.equals(type(ws_server.start), "function", "start should be function")
      assert.equals(type(ws_server.stop), "function", "stop should be function")
    end)
    
    it("should have port configuration", function()
      setup()
      assert.is_true(ws_server.port == nil or (type(ws_server.port) == "number" and ws_server.port > 0), "Port should be nil before start or a positive number")
    end)
    
    it("should have WebSocket helper functions", function()
      setup()
      assert.not_nil(ws_server.generate_accept_key, "Should have generate_accept_key")
      assert.not_nil(ws_server.parse_websocket_frame, "Should have parse_websocket_frame")
      assert.not_nil(ws_server.handle_message, "Should have handle_message")
    end)
    
    it("should generate WebSocket accept key", function()
      setup()
      -- Test with a known key (from WebSocket spec)
      local test_key = "dGhlIHNhbXBsZSBub25jZQ=="
      local accept = ws_server.generate_accept_key(test_key)
      
      assert.not_nil(accept, "Should generate accept key")
      assert.equals(type(accept), "string", "Accept key should be string")
      -- The expected result for this test key according to WebSocket spec
      assert.equals(vim.trim(accept), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "Should generate correct accept key")
    end)
  end)
  
  describe("WebSocket frame parsing", function()
    it("should handle text frames", function()
      setup()
      
      -- Create a simple text frame (opcode 0x1)
      -- Frame: FIN=1, opcode=1 (text), no mask, payload="Hi"
      local frame = string.char(0x81, 0x02) .. "Hi"
      
      -- Mock client
      local mock_client = {
        write = function() end,
        close = function() end
      }
      
      -- Should not error when parsing valid frame
      local ok = pcall(ws_server.parse_websocket_frame, frame, mock_client)
      assert.is_true(ok, "Should parse text frame without error")
    end)
    
    it("should handle close frames", function()
      setup()
      
      -- Create a close frame (opcode 0x8)
      local frame = string.char(0x88, 0x00)
      
      local mock_client = {
        closed = false,
        write = function() end,
        close = function(self) self.closed = true end,
        ['end'] = function(self) self.closed = true end
      }
      
      -- Should handle close frame
      local ok = pcall(ws_server.parse_websocket_frame, frame, mock_client)
      assert.is_true(ok, "Should handle close frame")
    end)
    
    it("should handle ping frames", function()
      setup()
      
      -- Create a ping frame (opcode 0x9)
      local frame = string.char(0x89, 0x00)
      
      local pong_sent = false
      local mock_client = {
        write = function(self, data)
          -- Check if pong frame is sent (opcode 0xA)
          if data:byte(1) == 0x8A then
            pong_sent = true
          end
        end,
        close = function() end
      }
      
      ws_server.parse_websocket_frame(frame, mock_client)
      assert.is_true(pong_sent, "Should send pong in response to ping")
    end)
  end)
  
  describe("Message handling", function()
    it("should process WebSocket messages", function()
      setup()
      
      -- Mock a message payload
      local message = vim.json.encode({
        file = "test.js",
        line = 10,
        method = "log",
        args = {"test message"}
      })
      
      -- Should handle message without error
      local ok = pcall(ws_server.handle_message, message)
      assert.is_true(ok, "Should handle message without error")
    end)
  end)
  
  describe("Server lifecycle", function()
    it("should stop server cleanly", function()
      setup()
      
      -- Stop should not error even if not started
      local ok = pcall(ws_server.stop)
      assert.is_true(ok, "Should stop without error")
      
      -- After stop, server should be nil
      ws_server.stop()
      assert.nil_value(ws_server.server, "Server should be nil after stop")
    end)
    
    it("should track clients", function()
      setup()
      assert.not_nil(ws_server.clients, "Should have clients table")
      assert.equals(type(ws_server.clients), "table", "Clients should be table")
    end)
    
    it("should have remove_client function", function()
      setup()
      assert.not_nil(ws_server.remove_client, "Should have remove_client")
      assert.equals(type(ws_server.remove_client), "function", "remove_client should be function")
    end)
  end)
  
  describe("Command and client management", function()
    it("should send command to all clients", function()
      setup()
      
      local command_sent = false
      local mock_client = {
        is_closing = function() return false end,
        write = function(self, data)
          command_sent = true
          assert.is_true(#data > 0, "Should send data")
        end
      }
      
      ws_server.clients = { mock_client }
      ws_server.send_command("test_command", { foo = "bar" })
      
      assert.is_true(command_sent, "Should send command to clients")
    end)
    
    it("should enable clients", function()
      setup()
      
      local enable_sent = false
      local mock_client = {
        is_closing = function() return false end,
        write = function(self, data)
          local decoded = vim.json.decode(data:sub(3))
          if decoded and decoded.command == "enable" then
            enable_sent = true
          end
        end
      }
      
      ws_server.clients = { mock_client }
      ws_server.enable_clients()
      
      assert.is_true(enable_sent, "Should send enable command")
    end)
    
    it("should disable clients", function()
      setup()
      
      local disable_sent = false
      local mock_client = {
        is_closing = function() return false end,
        write = function(self, data)
          local decoded = vim.json.decode(data:sub(3))
          if decoded and decoded.command == "disable" then
            disable_sent = true
          end
        end
      }
      
      ws_server.clients = { mock_client }
      ws_server.disable_clients()
      
      assert.is_true(disable_sent, "Should send disable command")
    end)
    
    it("should shutdown clients", function()
      setup()
      
      local shutdown_sent = false
      local mock_client = {
        is_closing = function() return false end,
        write = function(self, data)
          local decoded = vim.json.decode(data:sub(3))
          if decoded and decoded.command == "shutdown" then
            shutdown_sent = true
          end
        end
      }
      
      ws_server.clients = { mock_client }
      ws_server.shutdown_clients()
      
      assert.is_true(shutdown_sent, "Should send shutdown command")
    end)
    
    it("should send_to_all_clients with proper frame encoding", function()
      setup()
      
      local data_received = nil
      local mock_client = {
        is_closing = function() return false end,
        write = function(self, data)
          data_received = data
        end
      }
      
      ws_server.clients = { mock_client }
      ws_server.send_to_all_clients({ type = "test", value = "hello" })
      
      assert.not_nil(data_received, "Should send data to client")
      assert.is_true(#data_received > 0, "Should have frame data")
    end)
    
    it("should skip closing clients when sending", function()
      setup()
      
      local sends = 0
      local mock_client_open = {
        is_closing = function() return false end,
        write = function(self, data) sends = sends + 1 end
      }
      local mock_client_closing = {
        is_closing = function() return true end,
        write = function(self, data) sends = sends + 1 end
      }
      
      ws_server.clients = { mock_client_open, mock_client_closing }
      ws_server.send_to_all_clients({ type = "test" })
      
      assert.equals(sends, 1, "Should only send to open client")
    end)
  end)
  
  describe("WebSocket client functionality", function()
    it("should create client connection", function()
      setup()
      
      local client = ws_server.create_client("127.0.0.1", 9229, "/test")
      
      assert.not_nil(client, "Should create client")
      assert.equals(client.host, "127.0.0.1", "Should set host")
      assert.equals(client.port, 9229, "Should set port")
      assert.equals(client.path, "/test", "Should set path")
      assert.is_false(client.connected, "Should not be connected initially")
      assert.not_nil(client.id, "Should have client ID")
      
      ws_server.close_client(client.id)
    end)
    
    it("should generate client handshake", function()
      setup()
      
      local handshake = ws_server.create_client_handshake("localhost", 8080, "/ws")
      
      assert.not_nil(handshake, "Should generate handshake")
      assert.is_true(handshake:match("GET /ws HTTP/1.1") ~= nil, "Should have correct path")
      assert.is_true(handshake:match("Host: localhost:8080") ~= nil, "Should have host header")
      assert.is_true(handshake:match("Upgrade: websocket") ~= nil, "Should have upgrade header")
      assert.is_true(handshake:match("Sec%-WebSocket%-Key:") ~= nil, "Should have WebSocket key")
    end)
    
    it("should generate random client key", function()
      setup()
      
      local key1 = ws_server.generate_client_key()
      local key2 = ws_server.generate_client_key()
      
      assert.not_nil(key1, "Should generate key")
      assert.equals(#key1, 16, "Key should be 16 characters")
      assert.not_equals(key1, key2, "Keys should be random")
    end)
    
    it("should queue messages before connection established", function()
      setup()
      
      local client = ws_server.create_client("127.0.0.1", 9229, "/test")
      
      ws_server.send_client_message(client.id, "test message 1")
      ws_server.send_client_message(client.id, "test message 2")
      
      local client_obj = ws_server.get_client(client.id)
      assert.equals(#client_obj.send_queue, 2, "Should queue messages when not connected")
      
      ws_server.close_client(client.id)
    end)
    
    it("should handle handshake response", function()
      setup()
      
      local client = ws_server.create_client("127.0.0.1", 9229, "/test")
      local handshake_response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n"
      
      ws_server.handle_client_data(client.id, handshake_response)
      
      local client_obj = ws_server.get_client(client.id)
      assert.is_true(client_obj.connected, "Should be connected after handshake")
      
      ws_server.close_client(client.id)
    end)
    
    it("should close client cleanly", function()
      setup()
      
      local client = ws_server.create_client("127.0.0.1", 9229, "/test")
      local client_id = client.id
      
      ws_server.close_client(client_id)
      
      local client_obj = ws_server.get_client(client_id)
      assert.nil_value(client_obj, "Should remove client from table")
    end)
    
    it("should get client by ID", function()
      setup()
      
      local client = ws_server.create_client("127.0.0.1", 9229, "/test")
      
      local retrieved = ws_server.get_client(client.id)
      assert.not_nil(retrieved, "Should get client by ID")
      assert.equals(retrieved.id, client.id, "Should be same client")
      
      ws_server.close_client(client.id)
    end)
    
    it("should track multiple clients", function()
      setup()
      ws_server.ws_clients = {}
      
      local client1 = ws_server.create_client("127.0.0.1", 9001, "/a")
      local client2 = ws_server.create_client("127.0.0.1", 9002, "/b")
      assert.not_nil(client1, "Should create first client")
      assert.not_nil(client2, "Should create second client")
      assert.equals(client1.port, 9001, "First client should have correct port")
      assert.equals(client2.port, 9002, "Second client should have correct port")
      
      ws_server.close_client(client1.id)
      ws_server.close_client(client2.id)
    end)
  end)

  describe("Frame draining", function()
    local websocket_frame = require('consolelog.communication.websocket_frame')

    local function connected_probe(received)
      setup()
      ws_server.ws_clients['probe'] = {
        id = 'probe',
        connected = true,
        buffer = "",
        send_queue = {},
        socket = { write = function() end, is_closing = function() return false end, close = function() end },
        on_message = function(payload) table.insert(received, payload) end,
      }
      return 'probe'
    end

    it("should deliver every frame arriving in one read", function()
      local received = {}
      local client_id = connected_probe(received)

      local burst = websocket_frame.create_text_frame("one", false)
          .. websocket_frame.create_text_frame("two", false)
          .. websocket_frame.create_text_frame("three", false)

      ws_server.handle_client_data(client_id, burst)

      assert.equals(#received, 3, "Should deliver all three batched frames")
      assert.equals(received[3], "three", "Should deliver the last frame payload")

      ws_server.ws_clients[client_id] = nil
    end)

    it("should buffer a frame split across reads", function()
      local received = {}
      local client_id = connected_probe(received)

      local whole = websocket_frame.create_text_frame(string.rep("x", 200), false)
      local split_at = math.floor(#whole / 2)

      ws_server.handle_client_data(client_id, whole:sub(1, split_at))
      assert.equals(#received, 0, "Should not deliver an incomplete frame")

      ws_server.handle_client_data(client_id, whole:sub(split_at + 1))
      assert.equals(#received, 1, "Should deliver the frame once complete")
      assert.equals(#received[1], 200, "Should reassemble the full payload")

      ws_server.ws_clients[client_id] = nil
    end)

    it("should deliver frames trailing the handshake response", function()
      setup()
      local received = {}
      local client = ws_server.create_client("127.0.0.1", 9229, "/test")
      client.on_message = function(payload) table.insert(received, payload) end

      local response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n"
          .. websocket_frame.create_text_frame("first event", false)

      ws_server.handle_client_data(client.id, response)

      assert.is_true(client.connected, "Should complete handshake")
      assert.equals(#received, 1, "Should deliver frame sent with the handshake response")
      assert.equals(received[1], "first event", "Should preserve trailing frame payload")

      ws_server.close_client(client.id)
    end)

    it("should reassemble a fragmented message", function()
      local received = {}
      local client_id = connected_probe(received)

      local first = string.char(0x01, 5) .. "hello"
      local middle = string.char(0x00, 1) .. " "
      local last = string.char(0x80, 5) .. "world"

      ws_server.handle_client_data(client_id, first)
      assert.equals(#received, 0, "Should not deliver until the final fragment")

      ws_server.handle_client_data(client_id, middle .. last)
      assert.equals(#received, 1, "Should deliver one assembled message")
      assert.equals(received[1], "hello world", "Should concatenate all fragments")

      ws_server.ws_clients[client_id] = nil
    end)

    it("should deliver a control frame interleaved in a fragmented message", function()
      local received = {}
      local client_id = connected_probe(received)

      local first = string.char(0x01, 4) .. "part"
      local ping = websocket_frame.create_ping_frame("", false)
      local last = string.char(0x80, 3) .. "ing"

      ws_server.handle_client_data(client_id, first .. ping .. last)

      assert.equals(#received, 1, "Should deliver the assembled message")
      assert.equals(received[1], "parting", "Should not let the ping corrupt reassembly")

      ws_server.ws_clients[client_id] = nil
    end)

    it("should return unconsumed bytes from parse_websocket_frame", function()
      setup()
      local mock_client = { write = function() end, close = function() end }

      local complete = websocket_frame.create_text_frame(vim.json.encode({ type = "ping", timestamp = 1 }), false)
      local partial = websocket_frame.create_text_frame("incomplete payload", false):sub(1, 6)

      local remaining = ws_server.parse_websocket_frame(complete .. partial, mock_client)

      assert.equals(remaining, partial, "Should return the incomplete tail for the next read")
    end)
  end)
end)
