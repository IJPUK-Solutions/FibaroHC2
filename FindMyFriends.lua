--[[
%% autostart
%% properties
%% weather
%% events
%% globals
--]]

-- should be https but the root certificates on the fibaro have not been updated
baseUrl = "http://api.ijpuk.com" 

-- Visit https://www.ijpuk.com to create an account and get your api key
local ijpukUserName = "Your username here"
local ijpukPassword = "Your password here"
local ijpukMailServerKey = "Your mail server key here"
local deleteMessageOnceProcessed = true -- Preferable to keep the size of your mail box small and fast.

local message = {
    ["matchConditions"] = {
        {
            ["regEx"] = "Joe Blogs (?'status'.+) Home",
            ["type"] = "setPresence",   --> Echo this info back, use later <--
            ["parts"] = {
              {
                ["variableName"] = "JoeHome",   --> Name of global variable <--
                ["regExGroupName"] = "status",
                ["matchConditions"] = {
                  "left",
                  "arrived at",
                  "is at"
                }
              }
            }
          },
          {
            ["regEx"] = "Tina Blogs (?'status'.+) Home",
            ["type"] = "setPresence",    --> Echo this info back, use later <--
            ["parts"] = {
              {
                ["variableName"] = "TinaHome",   --> Name of global variable <--
                ["regExGroupName"] = "status",
                ["matchConditions"] = {
                  "left",
                  "arrived at",
                  "is at"
                }
              }
            }
          }
    }
}

-- 
function setPresenceValue(globalVariableName, matchValue)
    if matchValue == "left" then
       fibaro:setGlobal(globalVariableName, "Away");
       fibaro:debug(globalVariableName .. " is now set to Away")
    elseif matchValue == "arrived at" or matchValue == "is at" then
        fibaro:setGlobal(globalVariableName, "Home");
        fibaro:debug(globalVariableName .. " is now set to Home")
    else 
        fibaro:debug("Unknown : globalVariableName : '" .. globalVariableName .. "' Match value : '" .. matchValue .. "'")
    end
    return true
end

function setGlobalValue(globalVariableName, value)
    if globalVariableName == "" or value == "" then
        return
    end
    fibaro:debug("Key: " .. globalVariableName .. " = " .. value)
    local oldValue = fibaro:getGlobalValue(globalVariableName);
    if oldValue == nil then
        fibaro:debug("Global variable not defined: " .. globalVariableName)
        return false
    end
    fibaro:setGlobal(globalVariableName, value);
    return true
end

---------------------- Please dont change below this line  ----------------------
local complete = true
local token = ""
local timeout = 10
local http = net.HTTPClient({timeout=2000})
local jsonData = json.encode(message)

-- Utility function to send requests to email bridge
function sendRequest(url, method, headers, data, next, fail)
    http:request(baseUrl .. url, 
    { 
        options = {
            method = method,
            headers = headers,
            data = data,
            timeout = 5000
        },
        success = function(response)
            local status = response.status
            if (status == 200 and next ~= nil) then
                next(response);
            elseif (status ~= 200 and fail ~= nil) then
                fail(response);
            end
        end,
        error = function(err)
            if (fail ~= nil) then
                fail(err);
            end
        end
    })
end

-- Send request to remove relevant messages from POP / IMAP server, 
-- we have processed them so they are no longer required
function deleteMessage(id)
    sendRequest("/api/v1/message/" .. id, "DELETE", {
        ['Authorization'] = "Bearer " .. token,
        ['mailServerKey'] = ijpukMailServerKey,
        ['Content-Type'] = "application/json"
    }, jsonData, 
        function() 
            fibaro:debug("Deleted message: " .. id)
        end, 
        function(response) 
            fibaro:debug("Failed to delete message: " .. id)
            if response ~= nil then
                if response.status == nil then
                    fibaro:debug(json.encode(response))
                elseif response.status == 429 then
                    fibaro:debug("Too many requests for subscription type - please upgrade")
                else
                    fibaro:debug("failed to delete message: " .. response.status)
                end
            end
        end
    )
end

function decode(d)
    local isError, err = pcall(
        function()                
            error({ data = json.decode(d) }) 
        end
    )
    if isError then
        local badData = json.encode(d)
        fibaro:debug(badData)
    end
    return err.data
end

function debugTable(tableData)
    for index, data in ipairs(tableData) do
        -- fibaro:debug(index)

        for key, value in pairs(data) do
            fibaro:debug(key .." " .. value)
        end
    end
end

-- Process the returned match results for relevant messages
function parseMessages(response)
    if response == nil then
        fibaro:debug("No response despite Parsing messages")
    elseif response.status == 200 then
        local result = decode(response.data)

        for i, data in ipairs(result.results) do
            local searchResponse = json.encode(data)
        
            local lastId = data.latestDirectMatchId
            local type = data.type
    
            for j, directMatch in ipairs(data.directMatches) do
                local id = directMatch.id
                local index = directMatch.index
                local subject = directMatch.subject
                local dateSend = directMatch.dateSent
                
                fibaro:debug("Processing: '" .. id .. " Index: " .. index .. " Subject: " .. subject)
                
                local gvName = ""
                local gvValue = ""
                local success = false

                for k, mv in ipairs(directMatch.matchValue) do 
                    if mv.variableName == "name" then
                        gvName = mv.matchValue
                    elseif mv.variableName == "value" then
                        gvValue = mv.matchValue
                    elseif mv.variableName == "JoeHome" and type == "setPresence" then
                        success = setPresenceValue(mv.variableName, mv.matchValue)
                    elseif mv.variableName == "TinaHome" and type == "setPresence" then
                        success = setPresenceValue(mv.variableName, mv.matchValue)
                    end                   
                end
                if type == "setGlobalVariable" then
                    success = setGlobalValue(gvName, gvValue)
                end
                if success then
                    if deleteMessageOnceProcessed then
                        deleteMessage(id)
                    end
                else
                    fibaro:debug("Message not deleted")
                end               
            end
        end
    else
        fibaro:debug("Status: " .. response.status) 
    end    
    timeout = 60
    complete = true
end

-- Send request to find messages on the POP / IMAP email server
function getMessages()
    sendRequest("/api/v1/message/search", "POST", {
        ['Authorization'] = "Bearer " .. token,
        ['mailServerKey'] = ijpukMailServerKey,
        ['Content-Type'] = "application/json"
    }, jsonData, parseMessages, authenticate)
end

-- Utility function to encode a string into Base64
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' 
function base64Enc(data) 
    return ((data:gsub('.', function(x) 
        local r, b='', x:byte() 
        for i=8, 1, -1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end 
        return r; 
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x) 
        if (#x < 6) then return '' end 
        local c=0 
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end 
        return b:sub(c+1,c+1) 
    end)..({ '', '==', '=' })[#data%3+1]) 
end 

local userNamePasswordBase64Encoded = base64Enc(ijpukUserName .. ":" .. ijpukPassword)

-- Need authentication token
function authenticate(err)
    sendRequest("/api/v1/authenticate", "POST", {
        ['Authorization'] = "Basic " .. userNamePasswordBase64Encoded
    }, "", 
    function(response)
        fibaro:debug("Logged in")
        local result = decode(response.data)
        if (result ~= nil) then
            token = result.token
            timeout = 60
        end
        complete = true
    end, 
    function(response)
        timeout = 120
        fibaro:debug("Authentication failed")
        if response ~= nil then
            if response.status == nil then
                fibaro:debug(json.encode(response))
            elseif response.status == 429 then
                fibaro:debug("Too many requests for subscription type - please upgrade")
            else
                fibaro:debug("failed authentication - Check your IJPUK credentials: " .. response.status)
            end
        end
        complete = true
    end);
end

-- Infinite loop - scheduled to loop every 10 / 60 / 120 seconds as defined above
function run()
    if (complete) then
        complete = false
        getMessages()
    end
    setTimeout(run, timeout * 1000); -- 1000 millis in 1 second
end

-- Start running --
run()
fibaro:debug("Running")