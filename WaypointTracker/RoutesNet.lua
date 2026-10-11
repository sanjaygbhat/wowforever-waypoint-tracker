-- Sharing routes and votes with other players of the addon, inside the game.
-- Addons can't reach the internet, so this talks to the players your client
-- can reach: a hidden chat channel everyone with the addon joins, your guild
-- and your group. Whatever arrives is kept, so lists and votes spread as
-- players come and go.
--
-- Messages (prefix WPTR, fields split by "^"):
--   A^id^v^author^cat^n^name   "I have this route" (yours, or one you keep)
--   Q^id^v                     "send me that route" (whispered)
--   R^id^v^seq^total^text      a piece of a route (whispered)
--   V^id^vote                  my own vote (1, -1, or 0 to take it back)
--   W^id:vote,id:vote,...      my own votes, for someone who just came online
--   H                          "I just came online": others say what they have
--   P^nonce                    the self-test's ping
local _, ns = ...
local L = ns.L

local Net = {}
ns.RoutesNet = Net

local PREFIX = "WPTR"
Net.CHANNEL = "WPTRoutes"
local CHUNK = 200 -- characters of route text per message
local MAX_TEXT = 12000 -- a route's text is never longer than this
local JOIN_DELAY = 15 -- seconds after logging in: the game's own channels come first
local ANNOUNCE_EVERY = 600 -- seconds between telling the channel about your routes
local REQUEST_MEMORY = 120 -- seconds before asking for the same route again
local PEER_MEMORY = 1800 -- seconds a player counts as "seen"

local stats = { sent = 0, got = 0, routes = 0, votes = 0 }
local peers = {} -- sender -> when we last heard from them
local queue = {} -- messages waiting: { msg, chat, target }
local tokens, MAX_TOKENS, REGEN = 8, 8, 1.1 -- the game lets an addon send ~1 message a second, in short bursts
local requested = {} -- id .. "#" .. v -> when we asked
local incoming = {} -- sender .. id .. v -> { total, parts, at }
local loopbackUntil = 0 -- the self-test: messages from yourself count
local testState

local function Routes()
    return ns.Routes
end

local function Sharing()
    return ns.Get("routeSharing") and true or false
end

-- Real routes shares the paths players walk and when boats leave (Trails.lua)
local function TravelSharing()
    return (ns.Get("realRoutes") and ns.Get("travelShare")) and true or false
end

local function WantChannel()
    return Sharing() or TravelSharing()
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
local function Enqueue(msg, chat, target)
    if #msg > 255 then
        return
    end
    queue[#queue + 1] = { msg = msg, chat = chat, target = target }
end

local THROTTLED = { [3] = true, [8] = true } -- Enum.SendAddonMessageResult: AddonMessageThrottle, ChannelThrottle

local function Pump(elapsed)
    tokens = math.min(MAX_TOKENS, tokens + elapsed / REGEN)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        wipe(queue)
        return
    end
    while tokens >= 1 and queue[1] do
        local q = table.remove(queue, 1)
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, q.msg, q.chat, q.target)
        if ok and (result == nil or result == true or result == 0) then
            tokens = tokens - 1
            stats.sent = stats.sent + 1
        elseif ok and THROTTLED[result] then
            table.insert(queue, 1, q) -- try again in a moment
            tokens = 0
            break
        end
    end
end

local function ChannelNumber()
    if not GetChannelName then
        return nil
    end
    local id = GetChannelName(Net.CHANNEL)
    id = tonumber(id)
    return id and id > 0 and id or nil
end

-- to everyone we can reach: the channel, the guild, the group
local function Broadcast(msg)
    local chan = ChannelNumber()
    if chan then
        Enqueue(msg, "CHANNEL", chan)
    end
    if IsInGuild and IsInGuild() then
        Enqueue(msg, "GUILD")
    end
    if IsInRaid and IsInRaid() then
        Enqueue(msg, "RAID")
    elseif IsInGroup and IsInGroup() then
        Enqueue(msg, "PARTY")
    end
end

local function Field(s, max)
    s = tostring(s or ""):gsub("[%^|\n\r]", " ")
    if #s > max then
        s = s:sub(1, max):gsub("[\192-\255][\128-\191]*$", "")
    end
    return s
end

local function AnnounceMsg(r)
    return table.concat({ "A", r.id, r.v or 1, Field(r.author, 60), r.cat or "other", #r.pts, Field(r.name, 60) }, "^")
end

-- the whole route, in pieces, to one player
local function SendRoute(r, target)
    local text = Routes().Serialize(r)
    if #text > MAX_TEXT then
        return 0
    end
    local total = math.ceil(#text / CHUNK)
    for i = 1, total do
        Enqueue(("R^%s^%d^%d^%d^%s"):format(r.id, r.v or 1, i, total, text:sub((i - 1) * CHUNK + 1, i * CHUNK)), "WHISPER", target)
    end
    return total
end

-- your routes that everyone may see
local function AnnounceMine()
    local st = Routes().Store()
    for _, r in pairs(st and st.list or {}) do
        if r.src == "mine" and r.public then
            Broadcast(AnnounceMsg(r))
        end
    end
end

-- a few routes you keep from others, so they spread while their maker is
-- offline (not the clearly disliked ones)
local GOSSIP = 3
local function Gossip()
    local R = Routes()
    local st = R.Store()
    local pool = {}
    for id, r in pairs(st and st.list or {}) do
        if r.src == "shared" and not R.IsLowRated(R.Score(id)) then
            pool[#pool + 1] = r
        end
    end
    for _ = 1, math.min(GOSSIP, #pool) do
        local i = math.random(1, #pool)
        Broadcast(AnnounceMsg(pool[i]))
        table.remove(pool, i)
    end
end

local function SendMyVotes(chat, target)
    local parts, len = {}, 2
    local function flush()
        if #parts > 0 then
            local msg = "W^" .. table.concat(parts, ",")
            if chat then
                Enqueue(msg, chat, target)
            else
                Broadcast(msg)
            end
            parts, len = {}, 2
        end
    end
    for id, v in pairs(Routes().MyVotes()) do
        local item = id .. ":" .. v
        if len + #item + 1 > 250 then
            flush()
        end
        parts[#parts + 1] = item
        len = len + #item + 1
    end
    flush()
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local function Split(msg)
    local out, from = {}, 1
    while true do
        local i = msg:find("^", from, true)
        if not i then
            out[#out + 1] = msg:sub(from)
            return out
        end
        out[#out + 1] = msg:sub(from, i - 1)
        from = i + 1
    end
end

local helloAnswered = 0
local handlers = {}
local listeners = {} -- other parts of the addon: tag -> fn(fields, sender)

-- Lets another part of the addon (Trails.lua) send and hear its own messages
-- on the same channel. Its messages wait behind the routes' ones and are
-- dropped when the queue is long: they're repeated later anyway.
function Net.Listen(tag, fn)
    listeners[tag] = fn
end

function Net.Share(msg)
    if not TravelSharing() or #queue > 6 then
        return false
    end
    Broadcast(msg)
    return true
end

handlers.A = function(f, sender)
    local R = Routes()
    local id, v, author = f[2], tonumber(f[3]), f[4]
    if not (R.ValidID(id) and v and author) or id:find("-", 1, true) then
        return
    end
    local st = R.Store()
    if not st or st.blocked[author] or author == R.Me() then
        return
    end
    local have = st.list[id]
    local key = id .. "#" .. v
    if have and (have.v or 1) >= v and (have.fromAuthor or sender ~= author) then
        return
    end
    if requested[key] and GetTime() - requested[key] < REQUEST_MEMORY then
        return
    end
    -- plenty waiting to go out already: ask later, when it's announced again
    if #queue > 40 then
        return
    end
    requested[key] = GetTime()
    Enqueue(("Q^%s^%d"):format(id, v), "WHISPER", sender)
end

handlers.Q = function(f, sender)
    local R = Routes()
    local r = R.ValidID(f[2]) and R.Get(f[2])
    if not r or (r.src == "mine" and not r.public) or r.src == "suggested" then
        return
    end
    SendRoute(r, sender)
end

handlers.R = function(f, sender)
    local R = Routes()
    local id, v, seq, total = f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if not (R.ValidID(id) and v and seq and total) or total < 1 or total > MAX_TEXT / CHUNK + 1 or seq < 1 or seq > total then
        return
    end
    local text = table.concat(f, "^", 6)
    local key = sender .. "#" .. id .. "#" .. v
    local box = incoming[key]
    if not box or box.total ~= total then
        box = { total = total, parts = {}, n = 0 }
        incoming[key] = box
    end
    box.at = GetTime()
    if not box.parts[seq] then
        box.parts[seq] = text
        box.n = box.n + 1
    end
    if box.n < total then
        return
    end
    incoming[key] = nil
    local route = R.Parse(table.concat(box.parts))
    if not route or route.id ~= id or route.v ~= v then
        return
    end
    local senderIsMe = sender == R.Me()
    local kept, isNew = R.Keep(route, sender, route.author == sender or (senderIsMe and testState ~= nil))
    if kept then
        stats.routes = stats.routes + 1
    end
    if testState and senderIsMe and testState.id == id then
        testState.gotRoute = GetTime()
    elseif kept and isNew and not requested[id .. "#" .. v] then
        -- sent to you without asking: say who from
        ns.Print(L.ROUTE_RECEIVED:format(kept.name, ns.Routes.ShortName(sender)))
    end
end

handlers.V = function(f, sender)
    Routes().HeardVote(f[2], sender, f[3])
    stats.votes = stats.votes + 1
end

handlers.W = function(f, sender)
    for id, v in (f[2] or ""):gmatch("([%w%-]+):(%-?%d)") do
        Routes().HeardVote(id, sender, v)
        stats.votes = stats.votes + 1
    end
end

handlers.H = function()
    -- answer once in a while, a little later, so a busy channel isn't flooded
    if GetTime() - helloAnswered < 60 then
        return
    end
    helloAnswered = GetTime()
    C_Timer.After(2 + math.random() * 10, function()
        AnnounceMine()
        SendMyVotes()
    end)
end

handlers.P = function(f, sender)
    if testState and sender == Routes().Me() and f[2] == testState.nonce then
        testState.gotPing = GetTime()
    end
end

function Net.OnMessage(prefix, msg, chat, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" or type(sender) ~= "string" then
        return
    end
    local R = Routes()
    sender = R.FullName(sender)
    if not sender then
        return
    end
    local me = R.Me()
    if sender == me and GetTime() > loopbackUntil then
        return
    end
    local f = Split(msg)
    -- each kind of message only while its sharing is on
    local fn
    if handlers[f[1]] then
        fn = Sharing() and handlers[f[1]]
    else
        fn = TravelSharing() and listeners[f[1]]
    end
    if not fn then
        return
    end
    -- the self-test only lets its own messages through
    if sender == me and not (f[1] == "R" or f[1] == "P") then
        return
    end
    stats.got = stats.got + 1
    if sender ~= me then
        peers[sender] = GetTime()
    end
    fn(f, sender)
end

-- ---------------------------------------------------------------------------
-- What you do in the Routes window
-- ---------------------------------------------------------------------------
-- Tell everyone about a route (yours, when you save it public).
function Net.Announce(id)
    local r = Routes().Get(id)
    if r and Sharing() and r.src ~= "suggested" and not (r.src == "mine" and not r.public) then
        Broadcast(AnnounceMsg(r))
    end
end

-- Send a whole route to one player (your target, or a name).
function Net.SendTo(id, name)
    local r = Routes().Get(id)
    if not r or type(name) ~= "string" or name == "" then
        return 0
    end
    return SendRoute(r, name)
end

-- ---------------------------------------------------------------------------
-- The channel
-- ---------------------------------------------------------------------------
local function HideChannel()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and ChatFrame_RemoveChannel then
            pcall(ChatFrame_RemoveChannel, f, Net.CHANNEL)
        end
    end
end

local joinedOnce = false
local function Join()
    if not WantChannel() then
        return
    end
    if not ChannelNumber() and JoinTemporaryChannel then
        pcall(JoinTemporaryChannel, Net.CHANNEL)
    end
    C_Timer.After(2, function()
        if ChannelNumber() then
            HideChannel()
            if not joinedOnce and Sharing() then
                joinedOnce = true
                Broadcast("H")
                AnnounceMine()
                SendMyVotes()
            end
        end
    end)
end

local function Leave()
    if ChannelNumber() and LeaveChannelByName then
        pcall(LeaveChannelByName, Net.CHANNEL)
    end
    joinedOnce = false
end

function Net.Status()
    local now, n = GetTime(), 0
    for _, at in pairs(peers) do
        if now - at < PEER_MEMORY then
            n = n + 1
        end
    end
    return {
        sharing = Sharing(),
        channel = ChannelNumber(),
        guild = IsInGuild and IsInGuild() or false,
        group = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil,
        peers = n, sent = stats.sent, got = stats.got, routes = stats.routes, votes = stats.votes,
        queued = #queue,
    }
end

-- ---------------------------------------------------------------------------
-- Self-test: /wp routes test. Sends a route to yourself in pieces by whisper
-- and pings the channel, then says what came back.
-- ---------------------------------------------------------------------------
function Net.SelfTest()
    local R = Routes()
    local m, x, y = ns.Geo.GetPlayerMapPosition()
    if not m then
        ns.Print(L.NO_POSITION, true)
        return
    end
    local pts = {}
    for i = 1, 40 do
        local a = (i - 1) / 40 * 2 * math.pi
        pts[i] = { m = m, x = ns.Clamp(x + math.cos(a) * 0.02, 0, 1), y = ns.Clamp(y + math.sin(a) * 0.02, 0, 1), t = tostring(i) }
    end
    local r = R.Validate({ id = R.NewID(), v = 1, name = L.ROUTE_TEST_NAME, cat = "other", mode = "loop", author = R.Me(), made = time(), pts = pts })
    testState = { id = r.id, nonce = tostring(math.random(100000, 999999)), at = GetTime() }
    loopbackUntil = GetTime() + 20
    -- make the copy that comes back count as someone else's, so it's kept
    local text = R.Serialize(r)
    local copy = R.Parse(text)
    copy.author = L.ROUTE_TEST_AUTHOR
    r = R.Validate(copy)
    r.src = "shared"
    local pieces = SendRoute(r, UnitName("player"))
    local chan = ChannelNumber()
    if chan then
        Enqueue("P^" .. testState.nonce, "CHANNEL", chan)
    end
    ns.Print(L.ROUTE_TEST_START:format(pieces), true)
    C_Timer.After(15, function()
        local t = testState
        testState = nil
        if not t then
            return
        end
        if t.gotRoute then
            ns.Print(L.ROUTE_TEST_WHISPER_OK:format(pieces, t.gotRoute - t.at), true)
        else
            ns.Print(L.ROUTE_TEST_WHISPER_FAIL, true)
        end
        if not chan then
            ns.Print(Sharing() and L.ROUTE_TEST_NO_CHANNEL or L.ROUTE_TEST_SHARING_OFF, true)
        elseif t.gotPing then
            ns.Print(L.ROUTE_TEST_CHANNEL_OK:format(chan), true)
        else
            ns.Print(L.ROUTE_TEST_CHANNEL_FAIL, true)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local pump = CreateFrame("Frame")
local announceAcc, cleanAcc = 0, 0
pump:SetScript("OnUpdate", function(_, elapsed)
    Pump(elapsed)
    announceAcc = announceAcc + elapsed
    if announceAcc >= ANNOUNCE_EVERY then
        announceAcc = 0
        if Sharing() then
            AnnounceMine()
            Gossip()
        end
    end
    cleanAcc = cleanAcc + elapsed
    if cleanAcc >= 30 then
        cleanAcc = 0
        local now = GetTime()
        for k, box in pairs(incoming) do
            if now - (box.at or 0) > 60 then
                incoming[k] = nil
            end
        end
    end
end)

ns.On("LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    C_Timer.After(JOIN_DELAY, Join)
end)

ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, chat, sender)
    Net.OnMessage(prefix, msg, chat, sender)
end)

ns.On("ROUTE_VOTED", function(id, v)
    if Sharing() then
        Broadcast(("V^%s^%d"):format(id, v))
    end
end)

ns.On("ROUTE_SAVED", function(id)
    Net.Announce(id)
end)

ns.On("SETTING_CHANGED", function(key)
    if key == "routeSharing" or key == "realRoutes" or key == "travelShare" then
        if WantChannel() then
            Join()
        else
            Leave()
        end
    end
end)
