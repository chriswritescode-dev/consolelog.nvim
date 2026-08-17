local M = {}
local bit = require("bit")

-- Seed random number generator once at module load
math.randomseed(os.time())

M.OPCODES = {
  CONTINUATION = 0x0,
  TEXT = 0x1,
  BINARY = 0x2,
  CLOSE = 0x8,
  PING = 0x9,
  PONG = 0xA
}

function M.parse_frame_header(data)
  if #data < 2 then
    return nil, "Insufficient data for header"
  end
  
  local byte1 = string.byte(data, 1)
  local byte2 = string.byte(data, 2)
  
  local header = {
    fin = bit.band(byte1, 0x80) == 0x80,
    rsv1 = bit.band(byte1, 0x40) == 0x40,
    rsv2 = bit.band(byte1, 0x20) == 0x20,
    rsv3 = bit.band(byte1, 0x10) == 0x10,
    opcode = bit.band(byte1, 0x0F),
    masked = bit.band(byte2, 0x80) == 0x80,
    payload_len = bit.band(byte2, 0x7F),
    header_len = 2,
    actual_payload_len = 0,
    mask_key = nil
  }
  
  header.actual_payload_len = header.payload_len
  
  if header.payload_len == 126 then
    if #data < 4 then
      return nil, "Insufficient data for 16-bit length"
    end
    header.actual_payload_len = string.byte(data, 3) * 256 + string.byte(data, 4)
    header.header_len = 4
  elseif header.payload_len == 127 then
    if #data < 10 then
      return nil, "Insufficient data for 64-bit length"
    end
    header.actual_payload_len = 0
    for i = 3, 10 do
      header.actual_payload_len = header.actual_payload_len * 256 + string.byte(data, i)
    end
    header.header_len = 10
  end
  
  if header.masked then
    if #data < header.header_len + 4 then
      return nil, "Insufficient data for mask key"
    end
    header.mask_key = {
      string.byte(data, header.header_len + 1),
      string.byte(data, header.header_len + 2),
      string.byte(data, header.header_len + 3),
      string.byte(data, header.header_len + 4)
    }
    header.header_len = header.header_len + 4
  end
  
  header.total_len = header.header_len + header.actual_payload_len
  
  return header, nil
end

function M.extract_frame(buffer)
  local header, err = M.parse_frame_header(buffer)
  if not header then
    return nil, nil, err
  end
  
  if #buffer < header.total_len then
    return nil, nil, "Incomplete frame"
  end
  
  local payload = string.sub(buffer, header.header_len + 1, header.total_len)
  
  if header.masked and header.mask_key then
    payload = M.unmask_payload(payload, header.mask_key)
  end
  
  local remaining = string.sub(buffer, header.total_len + 1)
  
  return {
    fin = header.fin,
    opcode = header.opcode,
    payload = payload
  }, remaining, nil
end

function M.drain_messages(buffer, fragments)
  local messages = {}
  local rest = buffer or ""
  fragments = fragments or {}

  while #rest > 0 do
    local frame, remaining = M.extract_frame(rest)
    if not frame then
      break
    end
    rest = remaining or ""

    if frame.opcode == M.OPCODES.CONTINUATION then
      if fragments.opcode then
        fragments.payload = fragments.payload .. frame.payload
        if frame.fin then
          table.insert(messages, { opcode = fragments.opcode, payload = fragments.payload })
          fragments.opcode = nil
          fragments.payload = nil
        end
      end
    elseif frame.opcode == M.OPCODES.TEXT or frame.opcode == M.OPCODES.BINARY then
      if frame.fin then
        table.insert(messages, { opcode = frame.opcode, payload = frame.payload })
      else
        fragments.opcode = frame.opcode
        fragments.payload = frame.payload
      end
    else
      table.insert(messages, { opcode = frame.opcode, payload = frame.payload })
    end
  end

  return messages, rest, fragments
end

function M.unmask_payload(payload, mask_key)
  local unmasked = {}
  for i = 1, #payload do
    local byte = string.byte(payload, i)
    local mask_byte = mask_key[((i - 1) % 4) + 1]
    unmasked[i] = string.char(bit.bxor(byte, mask_byte))
  end
  return table.concat(unmasked)
end

function M.mask_payload(payload, mask_key)
  return M.unmask_payload(payload, mask_key)
end

function M.create_frame(opcode, payload, masked)
  local frame = {}
  
  local byte1 = bit.bor(0x80, opcode)
  table.insert(frame, string.char(byte1))
  
  local payload_len = #payload
  local byte2 = masked and 0x80 or 0x00
  
  if payload_len < 126 then
    byte2 = bit.bor(byte2, payload_len)
    table.insert(frame, string.char(byte2))
  elseif payload_len < 65536 then
    byte2 = bit.bor(byte2, 126)
    table.insert(frame, string.char(byte2))
    table.insert(frame, string.char(math.floor(payload_len / 256)))
    table.insert(frame, string.char(payload_len % 256))
  else
    byte2 = bit.bor(byte2, 127)
    table.insert(frame, string.char(byte2))
    for i = 7, 0, -1 do
      table.insert(frame, string.char(math.floor(payload_len / (256 ^ i)) % 256))
    end
  end
  
  if masked then
    local mask_key = M.generate_mask_key()
    for i = 1, 4 do
      table.insert(frame, string.char(mask_key[i]))
    end
    payload = M.mask_payload(payload, mask_key)
  end
  
  table.insert(frame, payload)
  
  return table.concat(frame)
end

function M.generate_mask_key()
  local key = {}
  for i = 1, 4 do
    key[i] = math.random(0, 255)
  end
  return key
end

function M.create_text_frame(text, masked)
  return M.create_frame(M.OPCODES.TEXT, text, masked)
end

function M.create_binary_frame(data, masked)
  return M.create_frame(M.OPCODES.BINARY, data, masked)
end

function M.create_close_frame(code, reason, masked)
  local payload = ""
  if code then
    payload = string.char(math.floor(code / 256), code % 256)
    if reason then
      payload = payload .. reason
    end
  end
  return M.create_frame(M.OPCODES.CLOSE, payload, masked)
end

function M.create_ping_frame(data, masked)
  return M.create_frame(M.OPCODES.PING, data or "", masked)
end

function M.create_pong_frame(data, masked)
  return M.create_frame(M.OPCODES.PONG, data or "", masked)
end

return M