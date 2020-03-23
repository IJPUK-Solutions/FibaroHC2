--[[
%% autostart
%% properties
%% weather
%% events
%% globals
--]]

baseUrl = "https://api.ijpuk.com"

-- Visit https://www.ijpuk.com to create an account and get your doorbell key
local ijpukUserName = "Your username here"
local ijpukPassword = "Your password here"
local doorbellKey = "Your door bell key here"

---------------------- Please dont change below this line  ----------------------
local http = net.HTTPClient({timeout=2000})

-- Utility function to send requests to email bridge
function sendRequest(url, method, headers, data, next, fail)
    http:request(baseUrl .. url, 
    { 
        options = {
            method = method,
            headers = headers,
            data = data,
            timeout = 5000,
            checkCertificate = false 
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

sendRequest("/api/v1/Doorbell/" .. doorbellKey, "POST", {
    ['Authorization'] = "Basic " .. userNamePasswordBase64Encoded
}, "", function(response)        
        local result = decode(response.data)        
        if result ~= nil and result.success == true then
            fibaro:debug("Success response received")
        elseif result ~= nil and result.success == false then
            fibaro:debug("Error occured: " .. result.error)
        end
    end, 
    function(response)
        fibaro:debug("An error occurred")
        local status = response.status
        if status == 401 then
            fibaro:debug("Username or password were invalid or you need to relink your Amazon device")
        elseif status == 403 then
            fibaro:debug("Missing or expired Premium subscription")
        else
            fibaro:debug("An unknown error occurred : " .. status)
        end
    end
)
fibaro:debug("Sent")