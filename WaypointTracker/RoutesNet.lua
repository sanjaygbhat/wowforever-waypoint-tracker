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
local queue = {} -- messages waiting: { msg, chat, target, batch }
local tokens, MAX_TOKENS, REGEN = 8, 8, 1.1 -- the game lets an addon send ~1 message a second, in short bursts
local requested = {} -- id .. "#" .. v -> when we asked
local incoming = {} -- sender .. id .. v -> { total, parts, at }
local loopbackUntil = 0 -- the self-test: messages from yourself count
local testState

-- Whispers. A whisper to someone who has logged out, or who the server can't
-- reach (other faction, other realm), makes the game print "No player named
-- 'X' is currently playing." So the addon whispers only whoever the player
-- picked, or players it heard from directly (guild, group or a whisper) just
-- before; it stops whispering a name the server reports as gone, and hides
-- only the "not found" lines its own whispers caused.
local MAX_ASKS = 3 -- requests waiting for one sender
local REACH_WINDOW = 300 -- seconds after hearing a player directly that a reply to them may start
local GONE_FOR = 900 -- seconds a "not found" player is left alone
local ECHO_WINDOW = 30 -- seconds the server may take to say "not found"
local GONE_GRACE = 3 -- seconds pieces already in flight may still bounce once they're gone
local DIRECT = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
local direct = {} -- sender -> when we last heard them over guild, group or whisper
local gone = {} -- lower-case name -> until when we don't whisper them
local echoes = {} -- lower-case "name-realm" -> { target, keys, n = lines left to hide, untilAt }

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
local function Enqueue(msg, chat, target, batch, travel, explicit)
    if not (travel and TravelSharing() or not travel and Sharing()) or #msg > 255 then
        return
    end
    -- an automatic whisper remembers when its target last reached us
    local heardAt = chat == "WHISPER" and not explicit and direct[target] or nil
    queue[#queue + 1] = { msg = msg, chat = chat, target = target, batch = batch or {}, travel = travel,
        explicit = explicit, heardAt = heardAt }
end

-- The ways the game may print a whispered name, lower-case: "Name
-- Surname-Realm", "Name Surname" and (Forever surnames) "Name". The first
-- is the key.
local function NameKeys(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local full = name:lower()
    local keys = { [full] = true }
    local noRealm = full:match("^(.-)%-[^%-]*$") or full
    keys[noRealm] = true
    local first = noRealm:match("^(%S+)%s")
    if first then
        keys[first] = true
    end
    return full, keys
end

local function IsGone(name)
    local full = NameKeys(name)
    local untilAt = full and gone[full]
    return untilAt ~= nil and untilAt > GetTime()
end

-- whispers waiting to go out to one player are dropped
local function DropWhispers(target)
    for i = #queue, 1, -1 do
        local q = queue[i]
        if q.chat == "WHISPER" and q.target == target then
            table.remove(queue, i)
        end
    end
end

-- one transmission (a route in pieces, a request) is dropped
local function DropBatch(batch)
    for i = #queue, 1, -1 do
        if queue[i].batch == batch then
            table.remove(queue, i)
        end
    end
end

local function MarkGone(target)
    local full = NameKeys(target)
    if full then
        gone[full] = GetTime() + GONE_FOR
    end
    DropWhispers(target)
end

-- Whoever the player picked; a transmission that has started (a logout
-- part way through is caught by the "not found" reply); or a player who
-- reached us directly shortly before this whisper was queued or since.
-- A channel advert alone never proves the server lets us whisper them.
local function CanWhisper(q)
    if type(q.target) ~= "string" or q.target == "" or IsGone(q.target) then
        return false
    end
    if q.explicit or q.batch.started then
        return true
    end
    local at = math.max(q.heardAt or -math.huge, direct[q.target] or -math.huge)
    return GetTime() - at <= REACH_WINDOW
end

-- ERR_CHAT_PLAYER_NOT_FOUND_S as a pattern ("%s" or "%1$s" captures the
-- name); rebuilt only if the client's string changes.
local notFoundFmt, notFoundPattern
local function NotFoundPattern()
    local fmt = ns.Str(ERR_CHAT_PLAYER_NOT_FOUND_S)
    if fmt ~= notFoundFmt then
        notFoundFmt, notFoundPattern = fmt, false
        if fmt then
            fmt = fmt:gsub("%%1%$s", "%%s")
            if fmt:find("%s", 1, true) then
                local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
                notFoundPattern = "^" .. p:gsub("%%%%s", "(.+)", 1) .. "$"
            end
        end
    end
    return notFoundPattern
end

local function NotFoundName(msg)
    msg = ns.Str(msg)
    local pattern = msg and NotFoundPattern()
    return pattern and msg:match(pattern) or nil
end

-- The pending whisper record a "not found" line is about, if any: the
-- printed name must be one of the ways the game prints that target.
-- Records are few (whispers of the last half minute); the one with lines
-- left to hide and the earliest expiry wins.
local function EchoFor(msg)
    if not next(echoes) then
        return nil
    end
    local name = NotFoundName(msg)
    if not name then
        return nil
    end
    local key = name:lower()
    local full = ns.Routes and ns.Routes.FullName(name)
    full = full and full:lower()
    local now, best = GetTime(), nil
    for _, rec in pairs(echoes) do
        if rec.untilAt >= now and (rec.keys[key] or rec.keys[full]) then
            if not best or (rec.n > 0 and (best.n == 0 or rec.untilAt < best.untilAt)) then
                best = rec
            end
        end
    end
    return best
end

-- The game's CHAT_MSG_SYSTEM: someone we whispered isn't there. Runs even
-- when no chat window shows system messages.
local function OnSystemMessage(msg)
    local rec = EchoFor(msg)
    if rec then
        MarkGone(rec.target)
    end
end

-- Chat filter: hides one "not found" line per addon whisper that caused
-- it. Once a target is gone, only pieces already in flight may still
-- bounce (for a few seconds); after that the count is zero, so the
-- player's own /w to that name shows. Each chat window runs filters for
-- the same line, so remember the line.
local lastLine, lastMsg, lastAt, lastHide
local function SystemFilter(_, _, msg, ...)
    if not next(echoes) then
        return false
    end
    msg = ns.Str(msg)
    local lineID = ns.Plain(select(10, ...))
    local now = GetTime()
    if (lineID ~= nil and lineID == lastLine) or (lineID == nil and lastLine == nil and msg == lastMsg and now == lastAt) then
        return lastHide
    end
    lastLine, lastMsg, lastAt, lastHide = lineID, msg, now, false
    local rec = EchoFor(msg)
    if rec and rec.n > 0 then
        rec.n = rec.n - 1
        if not rec.goneAt then
            rec.goneAt = now
            rec.untilAt = math.min(rec.untilAt, now + GONE_GRACE)
        end
        MarkGone(rec.target)
        lastHide = true
    end
    return lastHide
end

-- The filter is added on the first whisper and removed when sharing is off.
local filterOn = false
local function SetFilter(on)
    if on == filterOn then
        return
    end
    local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
    local remove = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter
    -- older chat code: the same filters under their legacy global names
    if not add and ChatFrame_AddMessageEventFilter then
        add, remove = ChatFrame_AddMessageEventFilter, ChatFrame_RemoveMessageEventFilter
    end
    if on and add then
        filterOn = pcall(add, "CHAT_MSG_SYSTEM", SystemFilter) and true or false
    elseif not on then
        if remove then
            pcall(remove, "CHAT_MSG_SYSTEM", SystemFilter)
        end
        filterOn = false
    end
end

local function NoteWhisper(target)
    local full, keys = NameKeys(target)
    if not full then
        return
    end
    SetFilter(true)
    local rec = echoes[full]
    if not rec or rec.goneAt then
        rec = { target = target, keys = keys, n = 0 }
        echoes[full] = rec
    end
    rec.n = rec.n + 1
    rec.untilAt = GetTime() + ECHO_WINDOW
end

local function PruneQueue()
    for i = #queue, 1, -1 do
        local q = queue[i]
        if not (q.travel and TravelSharing() or not q.travel and Sharing()) then
            table.remove(queue, i)
        end
    end
end

local MAX_RETRIES, LOCKDOWN_DELAY, THROTTLE_DELAY = 5, 5, 2
local retryAt, failureShown = 0, false

local function SendFailed()
    if not failureShown then
        failureShown = true
        ns.Print(L.ROUTE_SEND_FAILED, true)
    end
end

local function Pump(elapsed)
    PruneQueue()
    tokens = math.min(MAX_TOKENS, tokens + elapsed / REGEN)
    if GetTime() < retryAt then return end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        if queue[1] then SendFailed() end
        wipe(queue)
        return
    end
    while tokens >= 1 and queue[1] do
        local q = table.remove(queue, 1)
        local whisper = q.chat == "WHISPER"
        if whisper and not CanWhisper(q) then
            -- not verifiably reachable: drop this transmission only (not
            -- what the player chose to send them)
            DropBatch(q.batch)
        else
            local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, q.msg, q.chat, q.target)
            local results = Enum and Enum.SendAddonMessageResult or {}
            result = ns.Plain(result)
            tokens = tokens - 1
            if ok and (result == nil or result == true or result == (results.Success or 0)) then
                stats.sent = stats.sent + 1
                if whisper then
                    q.batch.started = true
                    NoteWhisper(q.target)
                end
            elseif ok and whisper and (result == (results.TargetOffline or 12) or result == (results.TargetRequired or 6)) then
                -- the game already knows they're gone: stop, don't retry
                MarkGone(q.target)
            elseif ok and (result == (results.AddonMessageThrottle or 3)
                    or result == (results.ChannelThrottle or 8)
                    or result == (results.AddOnMessageLockdown or 11)) then
                q.retries = (q.retries or 0) + 1
                if q.retries <= MAX_RETRIES then
                    table.insert(queue, 1, q)
                else
                    -- Abandon this transmission's remaining fragments only at its
                    -- destination. ChannelThrottle restricts that channel, so also
                    -- drop pending announcements there without losing other sends.
                    local channel = q.chat == "CHANNEL" and result == (results.ChannelThrottle or 8)
                    for i = #queue, 1, -1 do
                        local pending = queue[i]
                        if pending.chat == q.chat and pending.target == q.target
                                and (channel or pending.batch == q.batch) then
                            table.remove(queue, i)
                        end
                    end
                    SendFailed()
                end
                local lockdown = result == (results.AddOnMessageLockdown or 11)
                retryAt = GetTime() + (lockdown and LOCKDOWN_DELAY or THROTTLE_DELAY)
                tokens = 0
                break
            else
                SendFailed()
            end
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

-- to everyone we can reach: the channel, the guild, the group. Route
-- adverts skip the shared channel: fetching a route means whispering its
-- advertiser, which only works for players who can reach us directly.
local function Broadcast(msg, batch, travel, noChannel)
    batch = batch or {}
    local chan = not noChannel and ChannelNumber()
    if chan then
        Enqueue(msg, "CHANNEL", chan, batch, travel)
    end
    if IsInGuild and IsInGuild() then
        Enqueue(msg, "GUILD", nil, batch, travel)
    end
    if IsInRaid and IsInRaid() then
        Enqueue(msg, "RAID", nil, batch, travel)
    elseif IsInGroup and IsInGroup() then
        Enqueue(msg, "PARTY", nil, batch, travel)
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

-- the whole route, in pieces, to one player (explicit: the player chose them)
local function SendRoute(r, target, explicit)
    if not Sharing() then return 0 end
    local text = Routes().Serialize(r)
    if #text > MAX_TEXT then
        return 0
    end
    local total = math.ceil(#text / CHUNK)
    local batch = {}
    for i = 1, total do
        Enqueue(("R^%s^%d^%d^%d^%s"):format(r.id, r.v or 1, i, total, text:sub((i - 1) * CHUNK + 1, i * CHUNK)), "WHISPER", target, batch, nil, explicit)
    end
    return total
end

-- your routes that everyone may see
local function AnnounceMine()
    local st = Routes().Store()
    for _, r in pairs(st and st.list or {}) do
        if r.src == "mine" and r.public then
            Broadcast(AnnounceMsg(r), nil, nil, true)
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
        Broadcast(AnnounceMsg(pool[i]), nil, nil, true)
        table.remove(pool, i)
    end
end

local function SendMyVotes(chat, target)
    local parts, len = {}, 2
    local batch = {}
    local function flush()
        if #parts > 0 then
            local msg = "W^" .. table.concat(parts, ",")
            if chat then
                Enqueue(msg, chat, target, batch)
            else
                Broadcast(msg, batch)
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
    Broadcast(msg, nil, true)
    return true
end

handlers.A = function(f, sender, chat)
    local R = Routes()
    local id, v, author = f[2], tonumber(f[3]), f[4]
    if not (R.ValidID(id) and v and author) or id:find("-", 1, true) then
        return
    end
    -- Asking means whispering the sender. Only ask players who reached us
    -- directly (guild, group): an advert on the shared channel can come
    -- from anyone, who may be gone or unreachable by the time we'd ask.
    if not DIRECT[chat] or IsGone(sender) then
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
    -- one sender at a time: at most a few open requests each
    local open = 0
    for _, q in ipairs(queue) do
        if q.chat == "WHISPER" and q.target == sender then
            open = open + 1
        end
    end
    if open >= MAX_ASKS then
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
        if not Sharing() then return end
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
    chat = ns.Str(chat)
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
        if DIRECT[chat] then
            direct[sender] = GetTime()
        end
    end
    fn(f, sender, chat)
end

-- ---------------------------------------------------------------------------
-- What you do in the Routes window
-- ---------------------------------------------------------------------------
-- Tell everyone about a route (yours, when you save it public).
function Net.Announce(id)
    local r = Routes().Get(id)
    if r and Sharing() and r.src ~= "suggested" and not (r.src == "mine" and not r.public) then
        Broadcast(AnnounceMsg(r), nil, nil, true)
    end
end

-- Send a whole route to one player (your target, or a name).
function Net.SendTo(id, name)
    if not Sharing() then return 0 end
    local r = Routes().Get(id)
    if not r or type(name) ~= "string" or name == "" then
        return 0
    end
    -- the player asked again: give a "not found" player another try
    local full = NameKeys(name)
    gone[full] = nil
    return SendRoute(r, name, true)
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
local function Leave()
    if ChannelNumber() and LeaveChannelByName then
        pcall(LeaveChannelByName, Net.CHANNEL)
    end
    joinedOnce = false
end

local function ReconcileChannel()
    if not WantChannel() then
        Leave()
        return
    end
    if ChannelNumber() then
        HideChannel()
        if not joinedOnce and Sharing() then
            joinedOnce = true
            Broadcast("H")
            AnnounceMine()
            SendMyVotes()
        end
    end
end

local function Join()
    if not WantChannel() then
        return
    end
    if not ChannelNumber() and JoinTemporaryChannel then
        pcall(JoinTemporaryChannel, Net.CHANNEL)
    end
    C_Timer.After(2, ReconcileChannel)
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
    if not Sharing() then
        ns.Print(L.ROUTE_TEST_SHARING_OFF, true)
        return
    end
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
    local pieces = SendRoute(r, R.Me(), true)
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
        for k, at in pairs(direct) do
            if now - at > REACH_WINDOW then direct[k] = nil end
        end
        for k, untilAt in pairs(gone) do
            if untilAt <= now then gone[k] = nil end
        end
        for k, rec in pairs(echoes) do
            if rec.untilAt < now then echoes[k] = nil end
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

-- "No player named 'X' is currently playing." after one of our whispers
ns.RegisterEvent("CHAT_MSG_SYSTEM", OnSystemMessage)

-- A join can complete after the two-second fallback, even after opting out.
ns.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", ReconcileChannel)

ns.On("ROUTE_VOTED", function(id, v)
    if Sharing() then
        Broadcast(("V^%s^%d"):format(id, v))
    end
end)

ns.On("ROUTE_SAVED", function(id)
    Net.Announce(id)
end)

ns.On("SETTING_CHANGED", function(key)
    if key == nil or key == "routeSharing" or key == "realRoutes" or key == "travelShare" then
        PruneQueue()
        if not Sharing() then
            wipe(incoming)
            wipe(requested)
            wipe(direct)
            wipe(echoes)
            SetFilter(false)
            testState = nil
            loopbackUntil = 0
            joinedOnce = false
        end
        if WantChannel() then
            Join()
        else
            Leave()
        end
    end
end)
