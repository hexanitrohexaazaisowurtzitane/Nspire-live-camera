-- THIS IS NOT THE ACTUAL CODE
-- ONLY HERE BECAUSE GITHUB DOESNT SUPPORT .TNS
-- TO MODIFY THE CODE, USE THE NSPIRE SOFTWARE


require "asi"
require "color"

-- Hello :-)
-- Theres a lot of stuff to do here, its barely just working
-- This script should be updated soon to support better optimization
-- and the rest of the features described on the readme

-- Todo:
-- Support for Discord integration
-- Support for LLM chat and image sending
-- Support for auto friends fetcher

-- All teto images present in the video demos were made by:
-- https://danbooru.donmai.us/posts?tags=moochaakaka&z=1
-- Since i did not ask for premission, i decided to remove them for now

--img_1 = image.new(_R.IMG.img_1)
--img_2 = image.new(_R.IMG.img_2)
--img_3 = image.new(_R.IMG.img_3)
img_name = image.new(_R.IMG.img_name)

local CONFIG = {
    WINDOW_BG = color.white,
    PIXEL_SIZE = 4,
    IMAGE_SIZE = 51,
    TIMER_INTERVAL = 1,
    STREAM_TIMER_INTERVAL = 0.1,
    READ_TIMEOUT = 500,
    WRITE_INTERVAL = 0.1,
    BUFFER_MAX_SIZE = 2048
}

local PORT_STATE = {
    IDLE = 1,
    CONNECTING = 2,
    STREAMING = 3,
    READING = 4
}

local STATE = {
    port = nil,
    rxString = "",
    data_in = false,
    image_streaming = true,
    request_stream = false,
    portState = PORT_STATE.IDLE,
    lastWrite = 0,
    buffer = {
        read = "",
        write = {}
    },
    decompressedCache = nil,
    isDataComplete = false,
    pendingProcess = false,
    lastFrameTime = 0,
    frameCount = 0,
    frameRate = 0
}

local SESSION = {
    menu = 0,
    editor_h = 27,
    messages = {"a:one little monkey jumping on a net","b:OH", 
    "a:one fell off", "a:and pumped his head", "b:OK!", "a:mama called the doctor,", 
    "a:doctor said", "b:HM?", "a:NO MORe MONKEYS", "a:jumping on the bed!", 
    "b:TELL EM!", "c:Nigger"},
    channel_id = nil,
    channel_nm = nil,
}

CACHE = {
    log = function(message)
        table.insert(CACHE.logs, message)
        if #CACHE.logs > 15 then
            table.remove(CACHE.logs, 1)
        end
        return CACHE.logs
    end,
    logs = {"                           -= WELCOME =-", 
            "                   Nspire Chat Connector | version 2.0.1", 
            "                © hexanitrohexaazaisowurtzitane @ github",
            "   Press [ menu ] to see the available controls.   ", "", 
    },
    infoStr = nil,
    disconnected_flag = false
}
function on.charIn(char) print(char) end
local W, H = platform.window:width(), platform.window:height()
local image_frame = (H - (CONFIG.IMAGE_SIZE * CONFIG.PIXEL_SIZE - 1)) / 2
local frame_size  = CONFIG.IMAGE_SIZE * CONFIG.PIXEL_SIZE

local colors = {
    ["A"]={255,255,255}, ["B"]={0,0,0}, ["C"]={255,0,0}, ["D"]={0,255,0},
    ["E"]={0,0,255}, ["F"]={255,255,0}, ["G"]={0,255,255}, ["H"]={255,0,255},
    ["I"]={255,165,0}, ["J"]={255,192,203},
    a={128,0,128}, b={165,42,42}, c={128,128,128}, d={0,255,0},
    e={173,216,230}, f={0,128,128}, g={0,0,128}, h={128,0,0},
    i={128,128,0}, j={255,215,0}, k={255,127,80}, l={250,128,114},
    m={75,0,130}, n={238,130,238}, o={64,224,208}, p={220,20,60},
    q={255,218,185}, r={230,230,250}, s={189,252,201}, t={245,245,220},
    u={240,230,140}, v={192,192,192}, w={210,105,30}, x={0,191,255},
    y={34,139,34}, z={64,64,64}
}

local colorCache = {}
for char, rgb in pairs(colors) do
    colorCache[char] = rgb
end

local function decodeRLE(input)
    if not input:find("%%") then return input end  -- Quick exit if no RLE encoding
    
    return input:gsub("%%(%d+)([^%%])%%", function(count, char)
        return string.rep(char, tonumber(count))
    end)
end

-- Bitwise AND operator implementation for Lua 5.1
local bit_and = function(a, b)
    local result, bitval = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

local base64_lookup = {}
do
    local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #base64_chars do
        base64_lookup[base64_chars:sub(i, i)] = i - 1
    end
end

local bit_patterns = {
    [0] = 1, [1] = 2, [2] = 4, [3] = 8, [4] = 16, [5] = 32
}

local treeNodeCache = {}
local function decompress(compressed_str)
    if STATE.decompressedCache and STATE.isDataComplete then
        return STATE.decompressedCache
    end
    
    _G["bit"] = _G["bit"] or {}
    _G["bit"]["band"] = _G["bit"]["band"] or bit_and
    
    compressed_str = decodeRLE(compressed_str)
    
    local orig_len, tree_size, rest = compressed_str:match("(%d+),(%d+),(.*)")
    if not orig_len or not tree_size or not rest then
        return ""  -- Invalid data format
    end
    
    orig_len, tree_size = tonumber(orig_len), tonumber(tree_size)
    
    local serialized_tree = rest:sub(1, tree_size)
    local encoded_data = rest:sub(tree_size + 1)
    
    local huffman_tree = treeNodeCache[serialized_tree]
    
    if not huffman_tree then
        local index = 1
        
        local function build_node()
            if index > #serialized_tree then
                return nil
            end
            
            local node_type = serialized_tree:sub(index, index)
            index = index + 1
            
            if node_type == "L" then
                local char = serialized_tree:sub(index, index)
                index = index + 1
                return {char = char}
            else
                local left = build_node()
                local right = build_node()
                return {left = left, right = right}
            end
        end
        
        huffman_tree = build_node()
        
        -- Cache the tree for reuse
        treeNodeCache[serialized_tree] = huffman_tree
    end
    
    -- Preallocate result array
    local result_parts = {}
    
    local i = 1
    local node = huffman_tree
    local result_length = 0
    
    -- chunks
    while i <= #encoded_data and result_length < orig_len do
        local value = base64_lookup[encoded_data:sub(i, i)]
        i = i + 1
        
        if value then
            -- each in 6-bit value
            for j = 5, 0, -1 do
                local bit = (bit_and(value, bit_patterns[j]) > 0) and 1 or 0
                
                if bit == 0 then
                    node = node.left
                else
                    node = node.right
                end
                
                if not node then
                    break
                end
                
                if node.char then
                    result_parts[#result_parts + 1] = node.char
                    result_length = result_length + 1
                    node = huffman_tree
                    
                    if result_length >= orig_len then
                        break
                    end
                end
            end
        end
    end
    

    local result = table.concat(result_parts)
    
    if STATE.isDataComplete then
        STATE.decompressedCache = result
    end
    
    return result
end


local function queueWrite(command)
    table.insert(STATE.buffer.write, command)
end


local function processBuffer()
    if not STATE.pendingProcess then return end
    

    local lastStartPos = STATE.buffer.read:match(".*()START_IMAGE")
    if not lastStartPos then 
        STATE.pendingProcess = false
        return 
    end
    
    
    local endPos = STATE.buffer.read:find("END_IMAGE", lastStartPos)
    if not endPos then 
        STATE.pendingProcess = false
        return 
    end
    
    
    local imageData = STATE.buffer.read:sub(lastStartPos + 11, endPos - 1)
    if #imageData > 1 then
        
        local currentTime = timer.getMilliSecCounter()
        if STATE.lastFrameTime > 0 then
            local frameTime = (currentTime - STATE.lastFrameTime) / 1000
            STATE.frameRate = 1 / frameTime
        end
        STATE.lastFrameTime = currentTime
        STATE.frameCount = STATE.frameCount + 1
        
        
        STATE.decompressedCache = nil
        STATE.rxString = imageData
        STATE.data_in = true
        STATE.image_streaming = true
        STATE.isDataComplete = true
        
        -- Keep only unprocessed data
        STATE.buffer.read = STATE.buffer.read:sub(endPos + 9)
        platform.window:invalidate()
    end
    
    STATE.pendingProcess = false
end


local function checkBufferSize()
    if #STATE.buffer.read > CONFIG.BUFFER_MAX_SIZE then
        local nextStart = STATE.buffer.read:find("START_IMAGE")
        
        if nextStart then
            STATE.buffer.read = STATE.buffer.read:sub(nextStart)
        else
            STATE.buffer.read = ""
        end
        
        STATE.isDataComplete = false
        STATE.decompressedCache = nil
    end
end

local function handlePortCommunication()
    if not STATE.port then return end
    
    local currentTime = timer.getMilliSecCounter()
    
    -- Read data but dont process immediately
    local success, data = pcall(STATE.port.getValue, STATE.port)
    if success and data and data ~= "" then
        data = data:gsub("[\r\n]+", "")
        STATE.buffer.read = STATE.buffer.read .. data
        STATE.pendingProcess = true
        
        checkBufferSize()
        
        if data:find("END_IMAGE") then
            STATE.isDataComplete = true
        else
            STATE.isDataComplete = false
        end
    end
    
    if STATE.pendingProcess then
        processBuffer()
    end
    
    if #STATE.buffer.write > 0 and (currentTime - STATE.lastWrite) >= CONFIG.WRITE_INTERVAL * 1000 then
        local command = table.remove(STATE.buffer.write, 1)
        STATE.port:write(command)
        STATE.lastWrite = currentTime
    end
end

local function handlePortDisconnect()
    if STATE.port then 
        STATE.port:disconnect()
        STATE.port = nil
    end
end


local function readListener(port)
    if not port then return end

    local success, data = pcall(port.getValue, port)
    if not success or not data then return end
    
    -- Just append to buffer
    data = data:gsub("[\r\n]+", "")
    STATE.buffer.read = STATE.buffer.read .. data
    if #STATE.rxString == 0 then 
        if data == '.' and #CACHE.logs[#CACHE.logs] < 77 then 
        CACHE.logs[#CACHE.logs] = CACHE.logs[#CACHE.logs]..data
        else 
            if #data > 100 then CACHE.logs = {} end
            table.insert(CACHE.logs, data)
        end
        platform.window:invalidate()
        print(data)
    end
    
    

    STATE.pendingProcess = true
    
    if data:find("END_IMAGE") then
        STATE.isDataComplete = true
        if not STATE.request_stream then
                print("Force stopping stream...")
                STATE.port:write("STOP\n")
                STATE.rxString = ""
                timer.stop()
                timer.start(CONFIG.TIMER_INTERVAL)
                return
            end
    end
end

local function portConnector(port, event)
    if event == asi.CONNECTED then
        asi.stopScanning()
        STATE.port = port
        port:setReadListener(readListener)
        --port:setBaudRate(asi.BAUD_RATE_9600)
        port:read(500)
        platform.window:invalidate()
    end
end


local function portScanner(port)
    port:connect(portConnector)
end

local function drawThickRect(gc,x,y,w,h)
        --gc:drawRect(x,y,w,h)
        gc:drawRect(x-1,y,w+2,h-1)
        gc:drawRect(x,y-1,w,h+1)
    end
function popMsg(gc, msg)
    gc:setFont("serif", "b", 9)
    local str_w = gc:getStringWidth(msg)
    local mid_f = ( W - str_w ) / 2 
    gc:setColorRGB(255,255,255)
    gc:fillRect(mid_f - 12, (H-23)/2-5, str_w + 25, 34)
    gc:setColorRGB(0,0,0)
    gc:drawString(msg, mid_f+1, (H-19)/2+1)
    drawThickRect(gc,mid_f - 9, (H-23)/2-2, str_w + 18, 28)
end
function popMsg2(gc, msg, msg2, h_push)
    if not h_push then h_push = 0 end
    gc:setFont("serif", "b", 9)
    local str_w = gc:getStringWidth(msg)
    
    local mid_f = ( W - str_w ) / 2 
    gc:setColorRGB(255,255,255)
    gc:fillRect(mid_f - 12 - 5, (H-23)/2-5 + h_push, str_w + 25 + 10, 34+13)
    gc:setColorRGB(0,0,0)
    gc:drawString(msg, mid_f+1, (H-19)/2+1+h_push)
    gc:setFont("serif", "b", 7)
    local str_w2= gc:getStringWidth(msg2)
    gc:drawString(msg2, (W-str_w2)/2, (H-19)/2+17+h_push)
    drawThickRect(gc,mid_f - 9 - 5, (H-23)/2-2 + h_push, str_w + 18 + 10, 28+13)
end

function drawImage(gc)
    if not STATE.request_stream then
        popMsg(gc, "Stopping Stream!")
        return
    elseif #STATE.rxString == 0 then
        popMsg(gc, "No image data!")
        return
    end
    
    local decoded_string
    if STATE.decompressedCache and STATE.isDataComplete then
        decoded_string = STATE.decompressedCache
    else
        decoded_string = decompress(STATE.rxString) 
        if STATE.isDataComplete then
            STATE.decompressedCache = decoded_string
        end
    end
    

    if not decoded_string or #decoded_string == 0 then
        gc:setColorRGB(255, 0, 0)
        gc:drawString("Invalid image data", 0, 10)
        return
    end
    
    local _size =  frame_size -4 
    --local _start = W - image_frame * 2 - _size - 2
    

    local pixelWidth = CONFIG.PIXEL_SIZE + 1
    local baseX = (W-frame_size)/2
    local baseY = image_frame - 1
    
    if not STATE.isDataComplete then
        --gc:drawString("Loading image...", 0, 30)
        CACHE.infoStr = "Decompressing "..#decoded_string.."bytes of pixel data"
    end
    
    -- Batch similar colors
    local lastChar = nil
    local lastColor = nil
    local pixelsToDraw = {}
    
    local x, y = 0, 0
    local count = 0
    
    for i = 1, #decoded_string do
        local char = decoded_string:sub(i, i)
        

        if char ~= lastChar then
            if #pixelsToDraw > 0 and lastColor then
                gc:setColorRGB(lastColor[1], lastColor[2], lastColor[3])
                for _, pixel in ipairs(pixelsToDraw) do
                    gc:fillRect(pixel[1], pixel[2], pixelWidth, pixelWidth)
                end
                pixelsToDraw = {}
            end
            
            lastChar = char
            lastColor = colorCache[char] or {0, 0, 0}
        end
        
        table.insert(pixelsToDraw, {baseX + x, baseY + y})
        
        count = count + 1
        x = x + CONFIG.PIXEL_SIZE
        if count >= CONFIG.IMAGE_SIZE then
            count = 0
            x = 0
            y = y + CONFIG.PIXEL_SIZE
        end
    end
    
    if #pixelsToDraw > 0 and lastColor then
        gc:setColorRGB(lastColor[1], lastColor[2], lastColor[3])
        for _, pixel in ipairs(pixelsToDraw) do
            gc:fillRect(pixel[1], pixel[2], pixelWidth, pixelWidth)
        end
    end
end

function on.construction()
    platform.window:setBackgroundColor(CONFIG.WINDOW_BG)
    cursor.set("default")
    
    asi.addStateListener(function(state)
        if state == asi.ON then
            asi.startScanning(portScanner)
        end
    end)
    
    timer.start(CONFIG.TIMER_INTERVAL)
    

    if drx then
        STATE.rxString = drx
        STATE.isDataComplete = true
        STATE.decompressedCache = nil
    end
    

    editor = D2Editor.newRichText()
    editor:setBorder(1)
    editor:setFontSize(10)
    editor:setMainFont("sansserif", "r")
    editor:setSizeChangeListener(function(editor, w, h) 
    SESSION.editor_h = h  platform.window:invalidate() end)
    editor:registerFilter {
        enterKey = function()
        if editor:getText() then 
        print("SEND:"..editor:getText()) 
        table.insert(SESSION.messages, "<sending...>")
        end
        editor:setText("") end,
    }
end

function on.destroy()
    handlePortDisconnect()
end


local function trimStart(str)
    return str:match("^%s*(.*)") or str
end

function drawWrappedText(gc, strings, W, startX, startY, lineSpace, tabSpace, excessSpace, n_msgs)
    if not strings or #strings == 0 then return startY end
    

    lineSpace = gc:getStringHeight("E") - 7
    local display_data = {}
    local cur_author = nil
    local maxWidth = W - startX - 1
    
    for _, text in ipairs(strings) do
        text = text:gsub("[\r\n]", "")
        
        local author, content = text:match("([^:]+):(.*)")
        
        if author and content then
            if author ~= cur_author then
                table.insert(display_data, "<author>" .. author .. ":")
                cur_author = author
            end
            
            local remainingText = tabSpace .. content
            
            while remainingText and #remainingText > 0 do
                local charIndex = 1
                
                while charIndex <= #remainingText do
                    local testLine = remainingText:sub(1, charIndex)
                    if gc:getStringWidth(testLine) > maxWidth then
                        charIndex = charIndex - 1
                        break
                    end
                    charIndex = charIndex + 1
                end
                
                if charIndex > #remainingText then
                    charIndex = #remainingText + 1
                end
                
                table.insert(display_data, remainingText:sub(1, charIndex - 1))
                remainingText = remainingText:sub(charIndex)
                if #remainingText > 0 then
                    remainingText = tabSpace .. excessSpace .. trimStart(remainingText)
                end
            end
        else
            local remainingText = text
            
            while remainingText and #remainingText > 0 do
                local charIndex = 1
                
                while charIndex <= #remainingText do
                    if gc:getStringWidth(remainingText:sub(1, charIndex)) > maxWidth then
                        charIndex = charIndex - 1
                        break
                    end
                    charIndex = charIndex + 1
                end
                
                if charIndex > #remainingText then
                    charIndex = #remainingText + 1
                end
                
                table.insert(display_data, remainingText:sub(1, charIndex - 1))
                
                remainingText = remainingText:sub(charIndex)
                if #remainingText > 0 then
                    remainingText = tabSpace .. excessSpace .. trimStart(remainingText)
                end
            end
        end
    end
    
    
    local i = 1
    while i < #display_data do
        local current = display_data[i]
        local next = display_data[i+1]
        
        if current and next and current:find("<author>") and 
           ((i < #display_data-1 and display_data[i+2] and display_data[i+2]:find("<author>")) or 
            (i == #display_data-1)) then
            
            display_data[i] = current .. next:sub(#tabSpace+1)
            table.remove(display_data, i+1)
        else
            i = i + 1
        end
    end
    
    local currentY = startY
    local startIndex = math.max(1, #display_data - n_msgs)
    
    for i = startIndex, #display_data do
        local content = display_data[i]
        
        if content:find("<author>") then
            content = content:sub(9)
            currentY = currentY + 2
        end
        
        if content == "<sending...>" then 
            gc:setFont("sansserif", "r", 6)
            gc:drawString(content, startX, currentY + 10)
        else 
            gc:drawString(content, startX, currentY) 
        end
        
        currentY = currentY + lineSpace + 2
    end
    
    return currentY
end

function on.timer()
    if not STATE.port then 
        return
    end
    
    STATE.port:read(500)
    
    if STATE.pendingProcess then
        processBuffer()
    end
    
    
    if STATE.data_in or STATE.pendingProcess then
        platform.window:invalidate()
        STATE.data_in = false
    end
end

function hideEditor()
    editor:setReadOnly(true)
    editor:setVisible(false)
end

function on.paint(gc)
    gc:setColorRGB(0, 0, 0) 
    gc:setFont("serif", "r", 7)
    --hideEditor()
    if SESSION.menu == 0 then
        --gc:setColorRGB(0, 0, 0)
        drawThickRect(gc, (W-250)/2,100,250,100)
        gc:drawImage(img_name, 65, 25)
        --gc:drawImage(img_1, 15+10, 10)
        gc:drawString("version 3.0.1", 215, 26)
        drawWrappedText(gc, CACHE.logs, 280, (W-220)/2-5, 110, 11, "" ,"", 9) 
        --return
    elseif SESSION.menu == 1 then
        editor:setReadOnly(false)
        editor:move(-1,H-SESSION.editor_h+2)
        editor:resize(W+2,SESSION.editor_h)
        editor:setVisible(true)
        --gc:drawLine(-1,H-editor_h+1,W,H-editor_h+1)
        gc:setFont("serif", "r", 10)
        drawWrappedText(gc, SESSION.messages, W, 3, 1, 11, "  " ,"", 12)   
        
        --gc:drawImage(img_2, (W-96)/2+3,28-2)
        popMsg2(gc, "Connecting to "..tostring(SESSION.channel_nm).." ", tostring(SESSION.channel_id), 18)  
        
    elseif SESSION.menu == 2 then
        drawWrappedText(gc, CACHE.logs, 280, (W-220)/2-5, 156, 1, "" ,"", 1)   
        --print(gc:getStringWidth("This will be uploaded and added to EEPROM of your Esp32!"))
        gc:drawString("This will be uploaded and saved to EEPROM on your Esp32!", (W-254)/2, H-26)
        gc:drawString("Please fill the credentials form below:", 30, 49)
        gc:drawString("ssid  ( name )", (W-230)/2+1, (H-34)/2-13)
        gc:drawString("password", (W-230)/2+1, (H+44)/2-13)
        drawThickRect(gc, (W-260)/2,(H-70)/2,260,110)
        gc:setFont("serif", "b", 12)
        gc:drawString("Connect to new Network", 29, 29)
        gc:drawRect((W-230)/2,(H-34)/2,230,23)
        gc:drawRect((W-230)/2,(H+44)/2,230,23)
        --gc:drawImage(img_3, 178,3)
        
        
        
    else
        if #STATE.rxString > 0 and STATE.request_stream then
            gc:drawRect((W - frame_size)/2 -2, image_frame-3, frame_size +4, frame_size +4) 
            gc:drawString(string.format("FPS: %.1f", STATE.frameRate), 2,-1)
        else
            gc:setFont("serif", "r", 9)
            drawWrappedText(gc, CACHE.logs, W, 3, 1, 11, "" ,"", 15)     
            STATE.rxString = ""
        end
        
        if STATE.port then drawImage(gc) end
    end
    if not STATE.port then
        popMsg(gc, "No Port Found!")
    end
    -- delete if low fps
    if STATE.port and STATE.port:getState() == asi.INVALID then 
    STATE.rxString = "" end
    
    if CACHE.infoStr then     
        gc:setFont("serif", "r", 7)
        local str_w = gc:getStringWidth(CACHE.infoStr) + 7
        gc:setColorRGB(255,255,255)
        gc:fillRect(-1, H-14, str_w, 20)
        gc:setColorRGB(0,0,0)
        gc:drawRect(-1, H-14, str_w, 20)
        gc:drawString(CACHE.infoStr, 2,H-13)
    end
    
end

function on.escapeKey()
    STATE.request_stream = false
    STATE.port:write("STOP\n")
end

function on.tabKey()
    CACHE.log("Attempting to begin streaming service...")
    if STATE.port then
        timer.stop()
        timer.start(CONFIG.STREAM_TIMER_INTERVAL)
        CACHE.infoStr = "Attempting to start stream"
        STATE.port:write("STREAM\n")
    else 
        CACHE.infoStr = "Failed to stream: No Port found!"
        CACHE.log("FAILED: Could not start new serivice")
        CACHE.log("FAILED: Could not find any available COM for connection")
        CACHE.log("FAILED: Failed to index Port, nil value")
        CACHE.log("Check for connections with the peripheral device")
    end
end




function changeChannel(id, name)
    SESSION.channel_id = id
    SESSION.channel_nm = tostring(name)
    CACHE.log("Attempting new connection to channel "..id)
    platform.window:invalidate()
end
menu = {
    
    {"Actions",
       {"Switch to Discord", function() 
           SESSION.menu = 1
           toolpalette.enable("Actions", "Switch to Discord", false) 
           toolpalette.enable("Actions", "Switch to Camera", true)
           toolpalette.enable("Camera", "Take Camera Picture", false)
           toolpalette.enable("Camera", "Start Camera Stream", false)
           --toolpalette.enable("Camera", "Stop Camera Stream", false)
           --toolpalette.enable("Camera", "Send Cached Picture", false)
           --toolpalette.enable("Camera", "Toggle Flash", false)
           platform.window:invalidate()
       end},
       {"Switch to Camera", function() 
           hideEditor()
           SESSION.menu = 3
           toolpalette.enable("Actions", "Switch to Camera", false)
           toolpalette.enable("Actions", "Switch to Discord", true) 
           
           toolpalette.enable("Camera", "Take Camera Picture", true)
           toolpalette.enable("Camera", "Start Camera Stream", true)
           --toolpalette.enable("Camera", "Stop Camera Stream", true)
           --toolpalette.enable("Camera", "Send Cached Picture", true)
           --toolpalette.enable("Camera", "Toggle Flash", true)
           CACHE.log("Note:Camera display should bind automatically once a capture or stream protocol starts!")
           platform.window:invalidate()
       end},
       "-",
       {"Send Cached Data", function() print(1) end},
       {"Clear Cached Data", function()
           STATE.infoStr = "Cleaning local cached data..."
           platform.window:invalidate()
           STATE.rxString = ""
           CACHE.logs = {"cache cleared", ""}
           SESSION.messages = {""}
       end},
       "-",
       {"Toggle Cool Mode", function() print(1) end},
       {"Open About Page", function() print(1) end},
    },
    {"Camera",
       {"Take Camera Picture", function() 
           STATE.rxString = ""
           STATE.infoStr = "Initializing static photo connection"
           
       end},
       {"Start Camera Stream", function() 
           SESSION.menu = 3
           STATE.rxString = ""
           STATE.request_stream = true
           CACHE.log("Attempting to begin streaming service...")
           if STATE.port then
               timer.stop()
               timer.start(CONFIG.STREAM_TIMER_INTERVAL)
               CACHE.log("Resetting timers...")
               CACHE.log("Waiting for external device")
               STATE.port:write("STREAM\n")
           else 
               CACHE.infoStr = "Failed to stream: No Port found!"
               CACHE.log("FAILED: Unable to start new streaming service")
               CACHE.log("FAILED: Could not find any available COM for connection")
               CACHE.log("FAILED: Failed to index Port, nil value")
               CACHE.log("Check for connections with the peripheral device")
               STATE.request_stream = false
           end
           platform.window:invalidate() 
       end},
       {"Stop Camera Stream", function() 
           STATE.rxString = ""
           STATE.request_stream = false
           STATE.infoStr = "Force stopping streamming session..."
           timer.stop()
           timer.start(CONFIG.TIMER_INTERVAL)
           if STATE.port then
               STATE.port:write("STOP\n")
           else
               CACHE.infoStr = "Failed to stream: No Port found!"
               CACHE.log("FAILED: Could not reach peripheral device.")
               CACHE.log("FAILED: Failed to index Port, nil value.")
           end
           platform.window:invalidate() 
       end},
       "-",
       {"Send Cached Picture", function() print(1) end},
       {"Toggle Flash", function() print(1) end},
    },
    {"Channel     ",
       {"Chat with Gemini", function() 
       SESSION.channel_id = "gemini3.7Pro"  SESSION.channel_nm = "GeminiAI"
       CACHE.log("Attempting new connection to defined model server api...") 
       platform.window:invalidate() end},
        "-",
        -- Make sure to update this with your discord contacts' channel ids and names
       {"Connect to NAME_1",       function() changeChannel("CHANNEL_ID_1",  "NAME_1"   )  end},
       {"Connect to NAME_2",   function() changeChannel("CHANNEL_ID_2", "NAME_2")  end},
       {"Connect to NAME_3",       function() changeChannel("CHANNEL_ID_3", "NAME_3"    ) end},
       {"Connect to NAME_4",     function() changeChannel("CHANNEL_ID_4", "NAME_4"  ) end},
       {"Connect to NAME_5", function() changeChannel("CHANNEL_ID_5", "NAME_5") end},
    },
    
    {"Serial",
        {"Edit Credentials", function()
            hideEditor()
            SESSION.menu = 2
            toolpalette.enable("Actions", "Switch to Camera",  true)
            toolpalette.enable("Actions", "Switch to Discord", true) 
            toolpalette.enable("Camera", "Take Camera Picture", false)
            toolpalette.enable("Camera", "Start Camera Stream", false)
            platform.window:invalidate()
        end},
        {"Reconnect to Port", function() print(1) end},
        {"Restart Peripheral", function() print(1) end},
        "-",
        {"Not Connected", function() end},
        {"Serial Baud rate: 115200", function() end},       
    },
    {"Back", {"< Home >   ", function()
    hideEditor()
    SESSION.menu = 0
    toolpalette.enable("Camera", "Take Camera Picture", false)
    toolpalette.enable("Camera", "Start Camera Stream", false)
    toolpalette.enable("Actions", "Switch to Camera",  true)
    toolpalette.enable("Actions", "Switch to Discord", true)
    platform.window:invalidate()
    end}, {"< Close >", function() end}}
}
toolpalette.register(menu)
toolpalette.enable("Camera", "Take Camera Picture", false)
toolpalette.enable("Camera", "Start Camera Stream", false)
--toolpalette.enable("Camera", "Stop Camera Stream", false)
--toolpalette.enable("Camera", "Send Cached Picture", false)
--toolpalette.enable("Camera", "Toggle Flash", false)
toolpalette.enable("Serial", "Reconnect to Port", false)        -- not available yet
toolpalette.enable("Serial", "Not Connected", false)        
toolpalette.enable("Serial", "Serial Baud rate: 115200", false)
