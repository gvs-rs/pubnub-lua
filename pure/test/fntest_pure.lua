require "pubnub"
local json = require("dkjson")

local params = {...}

local function getenv_ex(env, dflt)
    local s = os.getenv(env)
    return s or (dflt)
end

local pubkey = getenv_ex("PUBNUB_PUBKEY", (#params > 0) and params[1] or "demo")
local subkey = getenv_ex("PUBNUB_KEYSUB", (#params > 1) and params[2] or "demo")
local origin = getenv_ex("PUBNUB_ORIGIN", (#params > 2) and params[3] or "pubsub.pubnub.com")

local number = 10^9
local test_index = 0
local test_name
local test_passing
local expected_messages
local failed_tests = 0
local FILE
local LINE
local init = { publish_key   = pubkey,
               subscribe_key = subkey,
               secret_key    = nil,
               auth_key      = "abcd",
               ssl           = true,
               origin        = origin
             }

function __FILE__() return debug.getinfo(2, 'S').source end
function __LINE__() return debug.getinfo(2, 'l').currentline end

local publish_test_callback = function ( info )
    if not info[1] then
        print( test_index .. ".test - " .. test_name .. " : failed" ) 
        print ( "publish failed: " .. info[2] )
        test_passing = false
        failed_tests = failed_tests + 1
    end
end

local subscribe_test_callback = function ( message, ch )
    for k,v in pairs(expected_messages) do
        if (v == (json.encode(message) or message)) then
            if expected_channels then
                if (expected_channels[k] ~= ch) then
                    print( test_index .. ".test - " .. test_name .. " : failed" ) 
                    print( FILE .. ":" .. LINE .. ": " ..
                          "channel \"" .. ch .. "\" doesn't match on received message: " ..
                          (json.encode(message) or message) ..
                          " - expected channel = \"" .. expected_channels[k] .. "\"" )
                    if test_passing then
                        failed_tests = failed_tests + 1
                        test_passing = false
                    end
                end
                table.remove(expected_channels, k)
            end
            table.remove(expected_messages, k)
            break
        end
    end
end

local presence = function(message, ch)
    print ( "presence - " .. ch .. " : " .. ( json.encode(message) or message ) )
end

local function received_expected_messages( __file__, __line__ )
    if (test_passing and (#expected_messages ~= 0)) then
        print ( test_index .. ".test - " .. test_name .. " : failed" ) 
        print(__file__ .. ":" .. __line__ .. ": " ..
              "remaining expected messages are not received: " ..
              table.concat(expected_messages, ",") )
        failed_tests = failed_tests + 1
        test_passing = false
    end
    return test_passing
end

local function subscribe_and_check( pn,
                                    chan,
                                    time_s,
                                    message_list,
                                    channel_list,
                                    __file__,
                                    __line__  )
    local t0 = os.time()
    expected_messages = message_list
    expected_channels = channel_list
    FILE = __file__
    LINE = __line__
    while (test_passing and
           (#expected_messages ~= 0) and
           (os.difftime(os.time(), t0) < time_s)) do
        pn:subscribe ( {
            channel  = chan,
            timetoken = pn:get_timetoken(),
            callback = subscribe_test_callback,
            error = function ( err )
                transaction_failed(__file__, __line__, err)
            end
        } )
    end
    if not received_expected_messages(__file__, __line__) then return false end
    
    return true
end

local function transaction_failed( __file__, __line__, response )
    print ( test_index .. ".test - " .. test_name .. " : failed" ) 
    print ( __file__ .. ":" .. __line__ .. ": transaction failed: " .. (response) )
    test_passing = false
    failed_tests = failed_tests + 1
end

local function start_test()
    test_passing = true
    test_index = test_index + 1
end

local function fntest_connect_and_send_over_single_channel()
    test_name = "connect_and_send_over_single_channel_lua"
    local chan = test_name .. "_" .. math.random(number)
    start_test()
    local pn = pubnub.new ( init )
    pn:subscribe ( {
        channel  = chan,
        callback = subscribe_test_callback,
        error = function ( err )
            transaction_failed(__FILE__(), __LINE__(), err)
        end,
        presence = presence
    } )
    if not test_passing then return end
    pn:publish ( {channel  = chan,
                  message  = "test Lua 1",
                  callback = publish_test_callback,
                  error = function ( response )
                      transaction_failed(__FILE__(), __LINE__(), response)
                  end
                 } )
    if not test_passing then return end
    pn:publish ( {channel  = chan,
                  message  = "test Lua 1-2",
                  callback = publish_test_callback,
                  error = function ( response )
                      transaction_failed(__FILE__(), __LINE__(), response)
                  end
                 } )
    if not test_passing then return end
    subscribe_and_check(pn,
                        chan,
                        5,
                        { "\"test Lua 1\"" , "\"test Lua 1-2\"", },
                        nil,
                        __FILE__(),
                        __LINE__())
end

local function fntest_connect_and_send_over_several_channels()
    test_name = "connect_and_send_over_several_channels_lua"
    local chan_1 = test_name .. "_" .. math.random(number)
    local chan_2 = test_name .. "_" .. math.random(number)
    start_test()
    local pn = pubnub.new ( init )
    pn:subscribe ( {
        channel  = chan_1 .. "," .. chan_2,
        callback = subscribe_test_callback,
        error = function ( err )
            transaction_failed(__FILE__(), __LINE__(), err)
        end,
        presence = presence
    } )
    if not test_passing then return end
    pn:publish ( {channel  = chan_1,
                  message  = "test Lua M1",
                  callback = publish_test_callback,
                  error = function ( response )
                      transaction_failed(__FILE__(), __LINE__(), response)
                  end
                 } )
    if not test_passing then return end
    pn:publish ( {channel  = chan_2,
                  message  = "test Lua M1-2",
                  callback = publish_test_callback,
                  error = function ( response )
                      transaction_failed(__FILE__(), __LINE__(), response)
                  end
                 } )
    if not test_passing then return end
    subscribe_and_check(pn,
                        chan_1 .. "," .. chan_2,
                        5,
                        { "\"test Lua M1\"" , "\"test Lua M1-2\"", },
                        { [1] = chan_1, [2] = chan_2 },
                        __FILE__(),
                        __LINE__())
end

local function fntest_connect_and_receiver_over_single_channel()
    test_name = "connect_and_receiver_over_single_channel_lua"
    local chan = test_name .. "_" .. math.random(number)
    start_test()
    local pn_1 = pubnub.new ( init )
    --[[ For different pubnub objects 'init' tables must be different( locations in memory) --]] 
    local init_2 = { publish_key   = pubkey,
                     subscribe_key = subkey,
                     secret_key    = nil,
                     auth_key      = "abcd",
                     ssl           = true,
                     origin        = origin
                   }
    local pn_2 = pubnub.new ( init_2 )
    
    pn_1:subscribe ( {
        channel  = chan,
        callback = subscribe_test_callback,
        error = function ( err )
            transaction_failed(__FILE__(), __LINE__(), err)
        end,
        presence = presence
    } )
    if not test_passing then return end
    pn_2:publish ( {channel  = chan,
                    message  = "test - 3 - lua",
                    callback = publish_test_callback,
                    error = function ( response )
                        transaction_failed(__FILE__(), __LINE__(), response)
                    end
                 } )
    if not test_passing then return end
    expected_messages = { "\"test - 3 - lua\"" }
    expected_channels = nil
    pn_1:subscribe ( {
        channel  = chan,
        timetoken = pn_1:get_timetoken(),
        callback = subscribe_test_callback,
        error = function ( err )
            transaction_failed(__FILE__(), __LINE__(), err)
        end
    } )
    if not received_expected_messages(__FILE__(), __LINE__()) then return end
end

local function run_tests()
    math.randomseed(os.time())
    fntest_connect_and_send_over_single_channel()
    fntest_connect_and_send_over_several_channels()
    fntest_connect_and_receiver_over_single_channel()
    if ( failed_tests ~= 0 ) then
        print( failed_tests .. ((1 == failed_tests) and " test" or " tests") .. " failed." )
    else
        print( "All(" .. test_index .. ") tests passed." )
    end
end

run_tests()