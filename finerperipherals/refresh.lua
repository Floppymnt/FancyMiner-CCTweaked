-- remove two files
local filesToRemove = { "oreminer.lua", "oreminer_state.lua" }

for _, file in ipairs(filesToRemove) do
    if fs.exists(file) then
        fs.delete(file)
        print("Deleted: " .. file)
    else
        print("File not found: " .. file)
    end
end

-- download new file
local url = "https://raw.githubusercontent.com/Floppymnt/FancyMiner-CCTweaked/refs/heads/FinerPeripherals/finerperipherals/oreminer.lua"
local output = "oreminer.lua"

print("Downloading oreminer.lua...")
shell.run("wget", url, output)
print("Download complete.")
