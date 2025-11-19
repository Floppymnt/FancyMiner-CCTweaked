-- Finer Peripherals Ore Miner
-- Uses Geo Scanner to detect and mine specific ores
os.loadAPI("flex.lua")
os.loadAPI("dig.lua")

-- Configuration
local options_file = "flex_options.cfg" -- Added options_file variable
local CONFIG_FILE = "oremine.cfg"
local MAX_SCAN_RADIUS = 8
local FUEL_SLOT = 1
local TORCH_SLOT = 2
local BLOCK_SLOT = 3
local DEFAULT_MAX_DISTANCE = 100
local DEFAULT_MIN_ORES = 32
local modem_channel = 6464 -- Added modem_channel variable
-- Add protected block types
local PROTECTED_BLOCKS = {
    "minecraft:chest",
    "ironchest:",
    "sophisticatedstorage:",
    "minecraft:trapped_chest",
    "minecraft:barrel",
    "minecraft:shulker_box",
    "storagedrawers:",
    "minecraft:hopper",
    "turtle"
}

-- Config handling functions
local function createDefaultConfig()
    local file = fs.open(CONFIG_FILE, "w")
    file.writeLine("# Ore Miner Configuration")
    file.writeLine("# Format: key=value")
    file.writeLine("")
    file.writeLine("# Target ores (comma separated)")
    file.writeLine("target_ores=minecraft:diamond_ore,minecraft:iron_ore")
    file.writeLine("")
    file.writeLine("# Minimum ores to find before stopping")
    file.writeLine("min_ores=32")
    file.writeLine("")
    file.writeLine("# Maximum distance to travel")
    file.writeLine("max_distance=100")
    file.close()
    
    -- Print usage instructions
    flex.printColors("Configuration file created: " .. CONFIG_FILE, colors.yellow)
    flex.printColors("Please edit the configuration file and run the program again.", colors.lightBlue)
    flex.printColors("\nConfiguration options:", colors.white)
    flex.printColors("target_ores: Comma-separated list of ore names", colors.lightBlue)
    flex.printColors("min_ores: Minimum number of ores to find", colors.lightBlue)
    flex.printColors("max_distance: Maximum distance to travel", colors.lightBlue)
    flex.printColors("\nExample ore names:", colors.white)
    flex.printColors("minecraft:diamond_ore", colors.lightBlue)
    flex.printColors("minecraft:iron_ore", colors.lightBlue)
    flex.printColors("minecraft:gold_ore", colors.lightBlue)
    return false
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        return createDefaultConfig()
    end

    local file = fs.open(CONFIG_FILE, "r")
    local config = {
        target_ores = {},
        min_ores = DEFAULT_MIN_ORES,
        max_distance = DEFAULT_MAX_DISTANCE
    }
    
    for line in file.readLine do
        if line and line:sub(1,1) ~= "#" then
            local key, value = line:match("([^=]+)=(.+)")
            if key and value then
                key = key:gsub("%s+", "")
                value = value:gsub("%s+", "")
                
                if key == "target_ores" then
                    for ore in value:gmatch("([^,]+)") do
                        table.insert(config.target_ores, ore)
                    end
                elseif key == "min_ores" then
                    config.min_ores = tonumber(value) or DEFAULT_MIN_ORES
                elseif key == "max_distance" then
                    config.max_distance = tonumber(value) or DEFAULT_MAX_DISTANCE
                end
            end
        end
    end
    
    file.close()
    return config
end

-- Initialize peripherals
local geoScanner = peripheral.find("geoExplorer")
if not geoScanner then
    flex.send("No Geo Explorer found!", colors.red)
    return
end

-- Load configuration or use command line arguments
local config
local args = {...}
if #args > 0 then
    -- Use command line arguments if provided
    config = {
        target_ores = {},
        min_ores = tonumber(args[2]) or DEFAULT_MIN_ORES,
        max_distance = tonumber(args[3]) or DEFAULT_MAX_DISTANCE
    }
    
    for ore in string.gmatch(args[1], "([^,]+)") do
        table.insert(config.target_ores, ore)
    end
else
    -- Load from config file
    config = loadConfig()
    if not config then
        return -- Config file was created, exit program
    end
end

if #config.target_ores == 0 then
    flex.printColors("No target ores specified!", colors.red)
    flex.printColors("Please edit " .. CONFIG_FILE .. " or provide command line arguments:", colors.yellow)
    flex.printColors("Usage: oreminer <ore1,ore2,...> [min_ores] [max_distance]", colors.lightBlue)
    return
end

-- Statistics tracking
local oresFound = 0
local distanceTraveled = 0
local blocksDug = 0
-- Track last dug count when we last called checkProgress()
local last_dug_progress = dig.getdug() or 0

-- transmition functions
if fs.exists(options_file) then
 local file = fs.open("flex_options.cfg", "r")
 local line = file.readLine()
 while line ~= nil do
  if string.find(line, "modem_channel=") == 1 then
   modem_channel = tonumber( string.sub(
         line, 15, string.len(line) ) )
   break
  end --if
  line = file.readLine()
 end --while
 file.close()
end --if
-- Add debug prints around modem initialization
print("DEBUG: Attempting to initialize modem.")
local modem -- Make sure modem is declared here, outside of any function
local hasModem = false
local p = flex.getPeripheral("modem")
if #p > 0 then
    print("DEBUG: Modem peripheral found: " .. tostring(p[1]))
    hasModem = true
    modem = peripheral.wrap(p[1])
    -- No need to open modem if only using modem.transmit for broadcast on a specific channel
    print("DEBUG: Modem peripheral wrapped. Will attempt to transmit status on channel 6465.")
else
    print("DEBUG: No modem peripheral found during initialization. Status updates disabled.")
    -- The script can still run without a modem, but status updates won't work.
end

-- Add this function to gather and send status (DEFINED OUTSIDE any function)
local function sendStatus()
    -- Gather status data
    -- total_quarry_blocks is calculated once after initial descent

    local current_processed_blocks = dig.getBlocksProcessed() or 0
    local estimated_remaining_blocks = total_quarry_blocks - current_processed_blocks

    local estimated_time_remaining_seconds = -1 -- Default to -1 if cannot calculate
    local estimated_completion_time_str = "Calculating..."
    local estimated_time_remaining_duration_str = "Calculating..." -- Added: for remaining duration

    -- Calculate Estimated Time Remaining and Completion Time if we have enough info and a valid speed
    if type(estimated_remaining_blocks) == 'number' and estimated_remaining_blocks > 0 and type(avg_blocks_per_second) == 'number' and avg_blocks_per_second > 0 then
        estimated_time_remaining_seconds = estimated_remaining_blocks / avg_blocks_per_second

        -- Format the completion time using the local timezone
        local current_local_epoch_time_sec = (os.epoch("local") or 0) / 1000 -- Get current local time in seconds
        local estimated_completion_time_sec = current_local_epoch_time_sec + estimated_time_remaining_seconds
        estimated_completion_time_str = os.date("%Y-%m-%d %H:%M:%S", estimated_completion_time_sec)

        -- Format the remaining duration as MM:SS
        local minutes = math.floor(estimated_time_remaining_seconds / 60)
        local seconds = math.floor(estimated_time_remaining_seconds % 60)
        estimated_time_remaining_duration_str = string.format("%02d:%02d", minutes, seconds)

    elseif total_quarry_blocks > 0 and estimated_remaining_blocks <= 0 then
        estimated_completion_time_str = "Completed" -- Indicate if digging is theoretically done
        estimated_time_remaining_duration_str = "00:00" -- Duration is zero when completed
    end


    -- Get inventory summary (basic example)
    local inventory_summary = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            table.insert(inventory_summary, { name = item.name, count = item.count })
        end
    end
    -- Infer mining state; assumes mining when not stuck
    local is_mining_status = not dig.isStuck()


    local status_message = {
        type = "status_update", -- Indicate this is a status update
        id = os.getComputerID(), -- Include turtle ID
        label = os.getComputerLabel(), -- Include turtle label
        fuel = turtle.getFuelLevel(),
        position = { x = dig.getx(), y = dig.gety(), z = dig.getz(), r = dig.getr() },
        is_mining = is_mining_status, -- Reflect actual mining state
        estimated_completion_time = estimated_completion_time_str, -- Estimated completion date and time
        estimated_time_remaining = estimated_time_remaining_duration_str, -- Added: Estimated time remaining duration (MM:SS)
        total_quarry_blocks = total_quarry_blocks, -- Send total blocks for context
        dug_blocks = dig.getdug() or 0, -- Still send dug blocks, handle nil
        processed_blocks = current_processed_blocks, -- Send processed blocks for context
        ymin = ymin, -- Add ymin (minimum Y planned) to the status message
        inventory_summary = inventory_summary -- Include basic inventory summary
    }

    -- Send the status message on a specific channel
    local status_channel = modem_channel -- Channel for status updates
    if modem then -- Check if modem peripheral is available
        -- print("DEBUG: Attempting to transmit status on channel " .. status_channel) -- NEW DEBUG PRINT before transmit
        -- Transmit from modem_channel to status_channel for a broadcast
        modem.transmit(modem_channel, status_channel, status_message)
        -- print("DEBUG: Status update sent on channel " .. status_channel) -- Optional debug
    else
        -- print("DEBUG: sendStatus called but modem is nil. Cannot transmit.") -- NEW DEBUG PRINT if modem is nil
    end
end

-- checkProgress function (MODIFIED to call sendStatus and implement speed learning)
local function checkProgress()
    -- Print detailed progress information (keep this for console)
    term.setCursorPos(1,1)
    term.clearLine()
    flex.printColors("Pos: X="..tostring(dig.getx())..
                     ", Y="..tostring(dig.gety())..
                     ", Z="..tostring(dig.getz())..
                     ", Rot="..tostring(dig.getr()%360), colors.white)

    term.setCursorPos(1,2)
    term.clearLine()
    flex.printColors("Fuel: "..tostring(turtle.getFuelLevel()), colors.orange)

    term.setCursorPos(1,3)
    term.clearLine()
    flex.printColors("Dug: "..tostring(dig.getdug() or 0).." blocks", colors.lightBlue) -- Handle nil

    term.setCursorPos(1,4)


    -- Speed Learning Logic
    -- Use processed blocks for speed calculation base
    local current_processed_blocks = dig.getBlocksProcessed() or 0
    -- Only update if blocks were actually processed since the last check
    if current_processed_blocks > processed_at_last_check then
        local blocks_processed_this_check = current_processed_blocks - processed_at_last_check
        blocks_since_last_speed_check = blocks_since_last_speed_check + blocks_processed_this_check

        -- Check if threshold is met for speed recalculation
        if blocks_since_last_speed_check >= speed_check_threshold then
            local current_epoch_time_ms = os.epoch("local") or 0
            local time_elapsed_ms = current_epoch_time_ms - time_of_last_speed_check

            -- Avoid division by zero or very small times
            if type(time_elapsed_ms) == 'number' and time_elapsed_ms > 0 then
                local current_period_bps = blocks_since_last_speed_check / (time_elapsed_ms / 1000) -- Calculate speed for this period in blocks per second
                -- Check against math.huge and -math.huge as values, AND check for NaN using self-comparison
                 if type(current_period_bps) == 'number' and current_period_bps ~= math.huge and current_period_bps ~= -math.huge and current_period_bps == current_period_bps then -- **CORRECTED: Replaced not math.nan() with self-comparison**
                     -- Simple averaging: average the new rate with the existing average
                     avg_blocks_per_second = (avg_blocks_per_second + current_period_bps) / 2
                 else
                      print("DEBUG: current_period_bps is not a valid number for averaging (NaN, +Inf, or -Inf). Value: " .. tostring(current_period_bps)) -- Added debug print
                 end
            else
                -- If no time has elapsed or time is invalid, do not calculate or update speed for this period.
                 print("DEBUG: Skipping speed calculation due to zero or invalid time_elapsed_ms (" .. tostring(time_elapsed_ms) .. ").") -- Added debug print
            end


            -- Reset for the next speed check period
            blocks_since_last_speed_check = 0
            time_of_last_speed_check = current_epoch_time_ms -- Start next period timer from now

        end
    end
    -- Update processed_at_last_check for the next checkProgress call
    processed_at_last_check = current_processed_blocks


    -- Calculate Estimated Time Remaining in Seconds
    local estimated_time_remaining_seconds = -1 -- Default to -1 if cannot calculate
    -- Use processed blocks for ETA base
    local remaining_blocks_for_eta = total_quarry_blocks - current_processed_blocks

    if type(remaining_blocks_for_eta) == 'number' and remaining_blocks_for_eta > 0 and type(avg_blocks_per_second) == 'number' and avg_blocks_per_second > 0 then
        estimated_time_remaining_seconds = remaining_blocks_for_eta / avg_blocks_per_second
    end

    -- Format Estimated Time Remaining as MM:SS for local display
    local eta_display_str = "Calculating..."
    if type(estimated_time_remaining_seconds) == 'number' and estimated_time_remaining_seconds >= 0 then
        local minutes = math.floor(estimated_time_remaining_seconds / 60)
        local seconds = math.floor(estimated_time_remaining_seconds % 60)
        eta_display_str = string.format("%02d:%02d", minutes, seconds)
        if estimated_time_remaining_seconds == 0 then
            eta_display_str = "Done"
        end
    end

    -- Display ETA on local console
    term.setCursorPos(1,5) -- Example line, adjust as needed
    term.clearLine()
    flex.printColors("ETA: "..eta_display_str, colors.yellow) -- Use yellow for ETA


    -- Use os.epoch("utc") for timing comparison in milliseconds for status *sending*
    local current_epoch_time_ms_utc = os.epoch("utc") or 0 -- Get current epoch time in milliseconds (UTC for sending interval)
    local time_difference_ms = current_epoch_time_ms_utc - (last_status_sent_time or 0) -- Calculate difference in milliseconds

    -- print("DEBUG: Status check timing (Epoch UTC) - os.epoch(): "..tostring(current_epoch_time_ms_utc)..", last_status_sent_time: "..tostring(last_status_sent_time)..", difference: "..tostring(time_difference_ms)..", interval (ms): "..tostring(status_send_interval))

    -- Send status update periodically using os.epoch() for the check
    if type(current_epoch_time_ms_utc) == 'number' and time_difference_ms >= status_send_interval then
        -- print("DEBUG: Status send interval met (Epoch UTC). Calling sendStatus.")
        sendStatus()
        last_status_sent_time = current_epoch_time_ms_utc -- Update last sent time using epoch time in milliseconds
    -- else
        -- print("DEBUG: Status send interval not met (Epoch UTC).")
    end

    -- Update dug and ydeep for the next checkProgress call
    dug = dig.getdug() or 0 -- Corrected to get current dug value, handle nil
    ydeep = dig.gety() or 0 -- Update ydeep, handle nil

    -- checkReceivedCommand() -- Remove this if not doing remote control
end --function checkProgress()



-- Function to check and refuel from chest above start
local function refuelFromChest()
    local currentPos = {x = dig.getx(), y = dig.gety(), z = dig.getz()}
    
    -- Return to start
    dig.goto(0, 0, 0, 0)
    
    -- Get fuel from chest above
    turtle.select(FUEL_SLOT)
    while turtle.getItemCount(FUEL_SLOT) == 0 do
        if not turtle.suckUp() then
            flex.send("Waiting for fuel...", colors.red)
            sleep(5)
        end
    end
    
    -- Refuel
    turtle.refuel()
    
    -- Return to mining position
    dig.goto(currentPos.x, currentPos.y, currentPos.z, dig.getr())
end

-- Function to deposit items in chest behind start
local function depositItems()
    local currentPos = {x = dig.getx(), y = dig.gety(), z = dig.getz()}
    
    -- Return to start
    dig.goto(0, 0, 0, 180)  -- Face the chest
    
    -- Save the selected slot
    local selectedSlot = turtle.getSelectedSlot()
    
    -- Deposit everything except fuel, torches, and emergency blocks
    for slot = 1, 16 do
        turtle.select(slot)
        if slot ~= FUEL_SLOT and slot ~= TORCH_SLOT and slot ~= BLOCK_SLOT then
            turtle.drop()
        end
    end
    
    -- Restore selected slot
    turtle.select(selectedSlot)
    
    -- Return to mining position
    dig.goto(currentPos.x, currentPos.y, currentPos.z, dig.getr())
end

-- Function to check if a block should be protected
local function isProtectedBlock(blockName)
    if not blockName then return false end
    for _, protected in ipairs(PROTECTED_BLOCKS) do
        if blockName:find(protected) then
            return true
        end
    end
    return false
end

-- Add new configuration values
local TUNNEL_WIDTH = 3
local SCAN_RADIUS = 5
local TORCH_INTERVAL = 6
local VEIN_MAX_DISTANCE = 2 -- Maximum distance between ores to be considered same vein
local STATE_FILE = "oreminer_state.dat"

-- State tracking
local state = {
    position = {x = 0, y = 0, z = 0, r = 0},
    distanceTraveled = 0,
    oresFound = 0,
    currentVein = {},
    knownOres = {}, -- Format: {x=x, y=y, z=z, name=name, mined=bool}
    originPos = {x = 0, y = 0, z = 0}
}

-- Function to save state
local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Function to load state
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        state = textutils.unserialize(file.readLine())
        file.close()
        return true
    end
    return false
end

-- Function to calculate distance between two points (including diagonal)
local function getDistance(pos1, pos2)
    return math.max(
        math.abs(pos1.x - pos2.x),
        math.abs(pos1.y - pos2.y),
        math.abs(pos1.z - pos2.z)
    )
end

-- Function to check if an ore belongs to current vein
local function isPartOfVein(ore)
    for _, knownOre in ipairs(state.currentVein) do
        if getDistance(ore, knownOre) <= VEIN_MAX_DISTANCE then
            return true
        end
    end
    return false
end

-- Modified scan function to track veins
local function scanForOres()
    if not geoScanner then return {} end
    
    local ores = {}
    local scan = geoScanner.scan(SCAN_RADIUS)
    
    if not scan then return {} end
    
    -- Convert scanner coordinates to absolute coordinates
    for _, block in ipairs(scan) do
        if block and block.name and not isProtectedBlock(block.name) then
            if block.name:find("ore") and not block.name:find("chest") and not block.name:find("barrel") then
                for _, targetOre in ipairs(config.target_ores) do
                    if block.name == targetOre then
                        local absolutePos = {
                            x = state.position.x + block.x,
                            y = state.position.y + block.y,
                            z = state.position.z + block.z,
                            name = block.name
                        }
                        
                        -- Check if ore is already known
                        local isKnown = false
                        for _, known in ipairs(state.knownOres) do
                            if known.x == absolutePos.x and 
                               known.y == absolutePos.y and 
                               known.z == absolutePos.z then
                                isKnown = true
                                break
                            end
                        end
                        
                        if not isKnown then
                            table.insert(state.knownOres, absolutePos)
                            if isPartOfVein(absolutePos) then
                                table.insert(state.currentVein, absolutePos)
                                table.insert(ores, {
                                    x = block.x,
                                    y = block.y,
                                    z = block.z,
                                    name = block.name
                                })
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    
    return ores
end

-- Function to check and fill holes in a wall or floor
local function fillHole(direction)
    turtle.select(BLOCK_SLOT)
    if direction == "down" then
        if not turtle.detectDown() then
            turtle.placeDown()
            return true
        end
    elseif direction == "up" then
        if not turtle.detectUp() then
            turtle.placeUp()
            return true
        end
    elseif direction == "forward" then
        if not turtle.detect() then
            turtle.place()
            return true
        end
    end
    return false
end

-- Function to check wall and place block if needed, separate from floor/ceiling checks
local function fillWall()
    turtle.select(BLOCK_SLOT)
    if not turtle.detect() then
        dig.place()
        return true
    end
    return false
end

-- Function to dig 3x3 tunnel section
local function digTunnelSection()
    -- Store initial orientation
    local startR = dig.getr()
    
    -- Ensure we're facing forward (north = 0 degrees)
    dig.gotor(0)
    
    -- Bottom layer
    -- Dig and fill center floor
    dig.dig()
    if not turtle.detectDown() then
        turtle.select(BLOCK_SLOT)
        dig.placeDown()
    end
    
    -- Left side bottom
    dig.left()
    dig.dig()
    dig.fwd()
    -- Check and fill both floor and wall independently
    if not turtle.detectDown() then
        turtle.select(BLOCK_SLOT)
        dig.placeDown()
    end
    fillWall() -- Always check and fill wall regardless of floor
    dig.back()
    
    -- Right side bottom
    dig.right(2)
    dig.dig()
    dig.fwd()
    -- Check and fill both floor and wall independently
    if not turtle.detectDown() then
        turtle.select(BLOCK_SLOT)
        dig.placeDown()
    end
    fillWall() -- Always check and fill wall regardless of floor
    dig.back()
    dig.left()
    
    -- Middle layer
    dig.up()
    dig.dig()
    
    -- Left wall
    dig.left()
    dig.dig()
    dig.fwd()
    fillWall() -- Always check and fill wall
    dig.back()
    
    -- Right wall
    dig.right(2)
    dig.dig()
    dig.fwd()
    fillWall() -- Always check and fill wall
    dig.back()
    dig.left()
    
    -- Top layer
    dig.up()
    
    -- Center ceiling
    dig.dig()
    if not turtle.detectUp() then
        turtle.select(BLOCK_SLOT)
        dig.placeUp()
    end
    
    -- Left side top
    dig.left()
    dig.dig()
    dig.fwd()
    -- Check and fill both ceiling and wall independently
    if not turtle.detectUp() then
        turtle.select(BLOCK_SLOT)
        dig.placeUp()
    end
    fillWall() -- Always check and fill wall regardless of ceiling
    dig.back()
    
    -- Right side top
    dig.right(2)
    dig.dig()
    dig.fwd()
    -- Check and fill both ceiling and wall independently
    if not turtle.detectUp() then
        turtle.select(BLOCK_SLOT)
        dig.placeUp()
    end
    fillWall() -- Always check and fill wall regardless of ceiling
    dig.back()
    dig.left()
    
    -- Place torch if needed
    if state.distanceTraveled % TORCH_INTERVAL == 0 then
        turtle.select(TORCH_SLOT)
        dig.down(2)
        turtle.placeDown()
        dig.up(2)
    end
    
    -- Return to starting position
    dig.down(2)
    dig.gotor(startR)
    
    -- Ensure block slot is selected
    turtle.select(BLOCK_SLOT)
end

-- Modified main mining loop
local function mineOreVein()
    while #state.currentVein > 0 do
        -- Get next closest ore
        local closest = state.currentVein[1]
        local minDist = math.huge
        
        for i, ore in ipairs(state.currentVein) do
            local dist = getDistance(state.position, ore)
            if dist < minDist then
                minDist = dist
                closest = ore
            end
        end
        
        -- Mine the ore
        if mineToCoordinates(
            closest.x - state.position.x,
            closest.y - state.position.y,
            closest.z - state.position.z
        ) then
            -- Remove from vein and mark as mined
            for i, ore in ipairs(state.currentVein) do
                if ore.x == closest.x and 
                   ore.y == closest.y and 
                   ore.z == closest.z then
                    table.remove(state.currentVein, i)
                    break
                end
            end
            for i, ore in ipairs(state.knownOres) do
                if ore.x == closest.x and 
                   ore.y == closest.y and 
                   ore.z == closest.z then
                    ore.mined = true
                    break
                end
            end
        end
        
        -- Scan for new connected ores
        scanForOres()
        saveState()
        -- After vein mining actions, call checkProgress() when total broken blocks crosses multiples of 9
        local current_dug = dig.getdug() or 0
        if math.floor(current_dug / 9) > math.floor(last_dug_progress / 9) then
            checkProgress()
        end
        last_dug_progress = current_dug
    end
end

-- Main mining loop
flex.send("Starting ore mining operation...", colors.yellow)
flex.send("Target ores: " .. table.concat(config.target_ores, ", "), colors.lightBlue)
flex.send("Minimum ores: " .. config.min_ores, colors.lightBlue)
flex.send("Maximum distance: " .. config.max_distance, colors.lightBlue)

-- Always start facing forward (0 degrees)
dig.gotor(0)

-- Create initial entry tunnel (4 blocks)
flex.send("Creating entry tunnel...", colors.yellow)
for i = 1, 4 do
    digTunnelSection()
    -- Move forward while maintaining orientation
    dig.gotor(0)  -- Ensure we're facing forward
    if dig.fwd() then
        state.distanceTraveled = state.distanceTraveled + 1
        state.position = {
            x = dig.getx(),
            y = dig.gety(),
            z = dig.getz(),
            r = dig.getr()
        }
        saveState()
        -- Call checkProgress() each time total broken blocks crosses a multiple of 9
        local current_dug = dig.getdug() or 0
        if math.floor(current_dug / 9) > math.floor(last_dug_progress / 9) then
            checkProgress()
        end
        last_dug_progress = current_dug
    end
end

-- Now continue with main mining loop
while state.distanceTraveled < config.max_distance and state.oresFound < config.min_ores do
    -- Check fuel
    if turtle.getFuelLevel() < 100 then
        refuelFromChest()
    end
    
    if turtle.getItemCount(14) > 0 then
        depositItems()
    end
    
    -- Dig tunnel section and move forward
    digTunnelSection()
    
    -- Move forward at ground level
    dig.gotor(0)  -- Ensure we're facing forward
    if dig.fwd() then
        state.distanceTraveled = state.distanceTraveled + 1
        state.position = {
            x = dig.getx(),
            y = dig.gety(),
            z = dig.getz(),
            r = dig.getr()
        }
        saveState()
        -- Call checkProgress() each time total broken blocks crosses a multiple of 9
        local current_dug = dig.getdug() or 0
        if math.floor(current_dug / 9) > math.floor(last_dug_progress / 9) then
            checkProgress()
        end
        last_dug_progress = current_dug
    end
    
    -- Scan for ores after moving
    local ores = scanForOres()
    if #ores > 0 then
        flex.send("Found " .. #ores .. " matching ores nearby!", colors.green)
        mineOreVein()
    end
end

-- Return to start
flex.send("Mining operation complete!", colors.green)
flex.send("Total distance: " .. distanceTraveled .. "m", colors.lightBlue)
flex.send("Total ores: " .. oresFound, colors.lightBlue)
flex.send("Total blocks dug: " .. blocksDug, colors.lightBlue)

-- Ensure we're facing the right way before returning
dig.gotor(0)  -- Face the starting direction (north)
dig.goto(0, 0, 0, 0)  -- Return to start while maintaining orientation
depositItems()

os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")
