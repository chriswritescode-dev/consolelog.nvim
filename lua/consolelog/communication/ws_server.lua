local M = {}

local uv = vim.loop
local constants = require("consolelog.core.constants")
local message_processor = require("consolelog.processing.message_processor_impl")
local websocket_frame = require("consolelog.communication.websocket_frame")
local websocket_sha1 = require("consolelog.communication.websocket_sha1")

local function bytes_after_http_headers(data)
	local _, header_end = data:find("\r\n\r\n", 1, true)
	if not header_end then
		return ""
	end
	return data:sub(header_end + 1)
end

M.server = nil
M.port = nil
M.clients = {}
M.ws_clients = {} -- WebSocket clients for connecting to external servers

function M.start(port)
	if M.server then
		return M.port
	end

	if not port then
		local port_manager = require("consolelog.communication.port_manager")
		local project_ports = port_manager.get_project_ports()
		if not project_ports then
			vim.notify("ConsoleLog: Failed to allocate WebSocket port", vim.log.levels.ERROR)
			return nil
		end
		port = project_ports.ws_port
	end

	M.port = port
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("WS_SERVER", "Starting WebSocket server on port " .. M.port)

	local consolelog = require("consolelog")

	consolelog.clear()
	message_processor.reset_matched_lines()

	M.server = uv.new_tcp()
	M.server:bind("127.0.0.1", M.port)

	M.server:listen(128, function(err)
		if err then
			vim.notify("Failed to start WebSocket server: " .. err, vim.log.levels.ERROR)
			return
		end

		local client = uv.new_tcp()
		M.server:accept(client)

		table.insert(M.clients, client)
		debug_logger.log("WS_SERVER", "Client connected, total clients: " .. #M.clients)

		local buffer = ""
		local handshake_done = false
		local fragments = {}

		client:read_start(function(err, data)
			if err then
				M.remove_client(client)
				return
			end

			if data then
				buffer = buffer .. data

				if #buffer > constants.WEBSOCKET.MAX_FRAME_SIZE then
					buffer = ""
					M.remove_client(client)
					return
				end

				if not handshake_done and buffer:match("Sec%-WebSocket%-Key") then
					local key = buffer:match("Sec%-WebSocket%-Key: ([^\r\n]+)")
					if key then
						debug_logger.log("WS_SERVER", "WebSocket handshake initiated with key: " .. key)
						-- Now we can call generate_accept_key directly since it's pure Lua
						local accept_key = M.generate_accept_key(key)
						if not accept_key then
							debug_logger.log("WS_SERVER", "Failed to generate accept key")
							M.remove_client(client)
							return
						end
						debug_logger.log("WS_SERVER", "Generated accept key: " .. accept_key)
						local response = "HTTP/1.1 101 Switching Protocols\r\n" ..
						    "Upgrade: websocket\r\n" ..
						    "Connection: Upgrade\r\n" ..
						    "Sec-WebSocket-Accept: " .. accept_key .. "\r\n" ..
						    "\r\n"
						client:write(response)
						handshake_done = true
						buffer = bytes_after_http_headers(buffer)
						debug_logger.log("WS_SERVER", "WebSocket handshake completed")
					end
				end

				if handshake_done and #buffer > 0 then
					debug_logger.log("WS_SERVER", "Data after handshake, buffer length: " .. #buffer)
					local ok, result = pcall(M.parse_websocket_frame, buffer, client, fragments)
					if ok then
						buffer = result or ""
					else
						debug_logger.log("WS_SERVER", "Parse error: " .. tostring(result))
						buffer = ""
					end
				end
			else
				M.remove_client(client)
				if #M.clients == 0 then
					vim.schedule(function()
						local consolelog = require("consolelog")
						consolelog.clear()
						message_processor.reset_matched_lines()
					end)
				end
			end
		end)
	end)

	return M.port
end

function M.generate_accept_key(key)
	local combined = key .. constants.WEBSOCKET.MAGIC_STRING
	
	-- Use pure Lua SHA1 implementation to avoid fast event context issues
	local sha1_hash = websocket_sha1.sha1(combined)
	local accept_key = websocket_sha1.base64_encode(sha1_hash)
	
	return accept_key
end

function M.send_to_all_clients(data)
	local debug_logger = require("consolelog.core.debug_logger")
	local payload = vim.json.encode(data)
	local frame = websocket_frame.create_text_frame(payload, false)
	
	for _, client in ipairs(M.clients) do
		if not client:is_closing() then
			client:write(frame)
		end
	end
	
	debug_logger.log("WS_SERVER", "Sent to all clients: " .. data.type)
end

function M.parse_websocket_frame(data, client, fragments)
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("WS_SERVER", "parse_websocket_frame called, data length: " .. #data)
	
	local frames, remaining = websocket_frame.drain_messages(data, fragments)

	for _, frame in ipairs(frames) do
		if frame.opcode == websocket_frame.OPCODES.TEXT then
			M.handle_message(frame.payload)
		elseif frame.opcode == websocket_frame.OPCODES.PING then
			local pong_frame = websocket_frame.create_pong_frame(frame.payload, false)
			client:write(pong_frame)
			debug_logger.log("WS_SERVER", "Sent pong response")
		elseif frame.opcode == websocket_frame.OPCODES.CLOSE then
			debug_logger.log("WS_SERVER", "Received close frame")
		else
			-- Ignore extension/reserved opcodes (like 0xC) - these are common in HMR scenarios
			debug_logger.log("WS_SERVER", "Ignoring extension opcode: " .. frame.opcode)
		end
	end

	return remaining
end

function M.handle_message(payload)
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("WS_SERVER", "Received message: " .. payload:sub(1, 100))
	
	if not M.has_received_message then
		M.has_received_message = true
		vim.schedule(function()
			vim.notify("ConsoleLog: WebSocket connected and receiving messages!", vim.log.levels.INFO)
		end)
	end

	local ok, message = pcall(vim.json.decode, payload)
	if not ok or not message then
		debug_logger.log("WS_SERVER", "Failed to parse JSON: " .. tostring(message))
		return
	end
	
	if message.type == "ping" then
		M.send_to_all_clients({ type = "pong", timestamp = message.timestamp })
		debug_logger.log("WS_SERVER", "Responded to ping")
	elseif message.type == "pong" then
		debug_logger.log("WS_SERVER", "Received pong")
	elseif message.type == "batch" and message.messages then
		debug_logger.log("WS_SERVER", "Processing batch of " .. #message.messages .. " messages")
		for i, msg in ipairs(message.messages) do
			if msg.type == "console" then
				debug_logger.log("WS_SERVER", string.format("Batch [%d/%d]: method=%s, file=%s, line=%s", 
					i, #message.messages,
					msg.method or "nil",
					msg.location and msg.location.file or "nil",
					msg.location and msg.location.line or "nil"))
				
				vim.schedule(function()
					local success = message_processor.process_message(msg)
					if not success then
						debug_logger.log("WS_SERVER", "Batch message " .. i .. " failed to process")
					end
				end)
				
				if msg.id then
					M.send_to_all_clients({ type = "ack", messageId = msg.id })
				end
			end
		end
	elseif message.type == "identify" then
		debug_logger.log("WS_SERVER", "Received identify message: projectId=" .. (message.projectId or "nil"))
	else
		debug_logger.log("WS_SERVER", "Single message: method=" .. (message.method or "nil") .. 
			", locationKey=" .. (message.locationKey or "nil") ..
			", executionIndex=" .. tostring(message.executionIndex or "nil") ..
			", location=" .. (message.location and (message.location.file or "?") .. ":" .. tostring(message.location.line or "?") or "nil"))
		
		if message.location then
			debug_logger.log("WS_SERVER", "Full location object: " .. vim.inspect(message.location))
		end

		vim.schedule(function()
			local success = message_processor.process_message(message)
			if not success then
				debug_logger.log("WS_SERVER", "Message processor failed to process message")
			else
				debug_logger.log("WS_SERVER", "Message processed successfully")
			end
		end)
		
		if message.id then
			M.send_to_all_clients({ type = "ack", messageId = message.id })
		end
	end
end

function M.remove_client(client)
	for i, c in ipairs(M.clients) do
		if c == client then
			table.remove(M.clients, i)
			break
		end
	end
	if not client:is_closing() then
		client:close()
	end
end

function M.send_command(command, data)
	local payload = vim.tbl_extend("force", data or {}, {
		type = "command",
		command = command,
		timestamp = vim.loop.now()
	})
	M.send_to_all_clients(payload)
end

function M.disable_clients()
	M.send_command("disable")
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("WS_SERVER", "Sent disable command to all clients")
end

function M.enable_clients()
	M.send_command("enable")
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("WS_SERVER", "Sent enable command to all clients")
end

function M.shutdown_clients()
	M.send_command("shutdown")
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("WS_SERVER", "Sent shutdown command to all clients")
end

function M.stop()
	M.shutdown_clients()
	
	vim.defer_fn(function()
		if M.server then
			M.server:close()
			M.server = nil
		end
		for _, client in ipairs(M.clients) do
			if not client:is_closing() then
				client:close()
			end
		end
		M.clients = {}
		M.port = nil
	end, 100)
end

-- WebSocket client functionality for connecting to external servers
function M.create_client(host, port, path)
	local debug_logger = require("consolelog.core.debug_logger")
	local client_id = "client_" .. #M.ws_clients + 1
	local client = {
		id = client_id,
		host = host,
		port = port,
		path = path or "/",
		socket = nil,
		connected = false,
		buffer = "",
		fragments = {},
		on_message = nil,
		on_close = nil,
		on_error = nil,
		on_connect = nil,
		send_queue = {}
	}
	
	debug_logger.log("WS_CLIENT", "Creating client to connect to " .. host .. ":" .. port .. (path or ""))
	M.ws_clients[client_id] = client
	
	-- Create TCP socket
	client.socket = uv.new_tcp()
	
	-- Connect to the server
	client.socket:connect(host, port, function(err)
		if err then
			debug_logger.log("WS_CLIENT", "Connection error: " .. tostring(err))
			if client.on_error then
				client.on_error(err)
			end
			return
		end
		
		debug_logger.log("WS_CLIENT", "Connected to server, sending handshake")
		-- Send WebSocket handshake
		local handshake = M.create_client_handshake(host, port, client.path)
		client.socket:write(handshake)
		
-- Start reading responses
		client.socket:read_start(function(read_err, data)
			if read_err then
				debug_logger.log("WS_CLIENT", "Read error: " .. tostring(read_err))
				if client.on_error then
					client.on_error(read_err)
				end
				M.close_client(client_id)
				return
			end
			
			if data then
				debug_logger.log("WS_CLIENT", "Received data: " .. #data .. " bytes, connected: " .. tostring(client.connected))
				if client.connected then
					debug_logger.log("WS_CLIENT", "Data content (first 100 bytes): " .. data:sub(1, 100))
				end
				M.handle_client_data(client_id, data)
			else
				-- Connection closed
				debug_logger.log("WS_CLIENT", "Connection closed - client.connected: " .. tostring(client.connected))
				if client.on_close then
					client.on_close()
				end
				M.close_client(client_id)
			end
		end)
	end)
	
	return client
end

function M.create_client_handshake(host, port, path)
	local key = M.generate_client_key()
	return string.format(
		"GET %s HTTP/1.1\r\n" ..
		"Host: %s:%d\r\n" ..
		"Upgrade: websocket\r\n" ..
		"Connection: Upgrade\r\n" ..
		"Sec-WebSocket-Key: %s\r\n" ..
		"Sec-WebSocket-Version: 13\r\n" ..
		"\r\n",
		path or "/", host, port, key
	)
end

function M.generate_client_key()
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local key = ""
	for i = 1, 16 do
		local rand = math.random(1, #chars)
		key = key .. chars:sub(rand, rand)
	end
	return key
end

function M.handle_client_data(client_id, data)
	local debug_logger = require("consolelog.core.debug_logger")
	local client = M.ws_clients[client_id]
	if not client then
		return
	end
	
	if not client.connected then
		debug_logger.log("WS_CLIENT", "Handling handshake response: " .. data:sub(1, 100))
		if not data:match("HTTP/1%.1 101") then
			debug_logger.log("WS_CLIENT", "Handshake failed, response: " .. data:sub(1, 200))
			return
		end

		debug_logger.log("WS_CLIENT", "WebSocket handshake successful!")
		client.connected = true
		client.buffer = bytes_after_http_headers(data)

		if client.on_connect then
			client.on_connect()
		end

		for _, msg in ipairs(client.send_queue) do
			M.send_client_message(client_id, msg)
		end
		client.send_queue = {}
	else
		client.buffer = (client.buffer or "") .. data
	end

	if #client.buffer == 0 then
		return
	end

	debug_logger.log("WS_CLIENT", "Processing WebSocket frames, buffered size: " .. #client.buffer)
	client.fragments = client.fragments or {}
	local frames, remaining = websocket_frame.drain_messages(client.buffer, client.fragments)
	client.buffer = remaining

	for _, frame in ipairs(frames) do
		if frame.opcode == websocket_frame.OPCODES.TEXT then
			debug_logger.log("WS_CLIENT", "Text frame received, payload size: " .. #frame.payload)
			if client.on_message then
				client.on_message(frame.payload)
			end
		elseif frame.opcode == websocket_frame.OPCODES.PING then
			debug_logger.log("WS_CLIENT", "Ping frame received, sending pong")
			local pong_frame = websocket_frame.create_pong_frame(frame.payload, false)
			client.socket:write(pong_frame)
		elseif frame.opcode == websocket_frame.OPCODES.CLOSE then
			debug_logger.log("WS_CLIENT", "Close frame received")
			M.close_client(client_id)
			return
		else
			debug_logger.log("WS_CLIENT", "Unhandled frame opcode: " .. frame.opcode)
		end
	end
end

function M.send_client_message(client_id, message)
	local debug_logger = require("consolelog.core.debug_logger")
	local client = M.ws_clients[client_id]
	if not client then
		debug_logger.log("WS_CLIENT", "Cannot send message - client not found: " .. client_id)
		return false
	end
	
	if not client.connected then
		debug_logger.log("WS_CLIENT", "Queueing message - client not connected yet: " .. client_id)
		-- Queue message if not connected yet
		table.insert(client.send_queue, message)
		return true
	end
	
	debug_logger.log("WS_CLIENT", "Sending message to client " .. client_id .. ": " .. message:sub(1, 100))
	local frame = websocket_frame.create_text_frame(message, true)
	client.socket:write(frame)
	return true
end

function M.get_client(client_id)
	return M.ws_clients[client_id]
end

function M.close_client(client_id)
	local client = M.ws_clients[client_id]
	if client and client.socket and not client.socket:is_closing() then
		client.socket:close()
	end
	M.ws_clients[client_id] = nil
end

return M
