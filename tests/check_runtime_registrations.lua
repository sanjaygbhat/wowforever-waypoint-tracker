-- Observe shipped registrations over load + repeated startup/window lifecycle.
-- Different listeners to the same event are allowed; registering the exact
-- same callback twice is rejected. SetScript overwrites and is not a duplicate.
-- Run at repo root: lua5.1 tests/check_runtime_registrations.lua
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns, seen, hooks, problems, registrations={},{},{},0,0
local function bad(file,line,entry,value,why)
    problems=problems+1
    print(('%s:%d: %s: value=%s: %s'):format(file,line,entry,tostring(value),why))
end
local create=CreateFrame
CreateFrame=function(...)
    local frame=create(...)
    local original=frame.HookScript
    frame.HookScript=function(self,script,fn)
        hooks[self]=hooks[self] or {}
        local key=hooks[self]
        key[script]=key[script] or {}
        if key[script][fn] then
            local info=debug.getinfo(2,'Sl')
            bad(info.short_src,info.currentline,'HookScript',script,'same callback already appended to this frame/script')
        end
        key[script][fn]=true
        return original(self,script,fn)
    end
    return frame
end
-- Bootstrap Core, then instrument the public subscriber functions before the
-- remaining TOC entries load. Do not load any entry twice.
assert(loadfile('WaypointTracker/Locales/enUS.lua'))('WaypointTracker',ns)
assert(loadfile('WaypointTracker/Core.lua'))('WaypointTracker',ns)
for _,method in ipairs({'On','RegisterEvent'}) do
    local original=ns[method]
    ns[method]=function(event,fn)
        registrations=registrations+1
        local key=method..':'..event
        seen[key]=seen[key] or {}
        if seen[key][fn] then
            local info=debug.getinfo(2,'Sl')
            bad(info.short_src,info.currentline,'ns.'..method,event,'same callback already subscribed to this event')
        end
        seen[key][fn]=true
        return original(event,fn)
    end
end
local loaded={['Locales/enUS.lua']=true,['Core.lua']=true}
local toc=assert(io.open('WaypointTracker/WaypointTracker.toc'))
local listed={}
for line in toc:lines() do
    if not line:match('^##') and line:match('%.lua%s*$') then
        local file=line:gsub('\\','/'):gsub('%s+$','')
        if listed[file] then bad('WaypointTracker/WaypointTracker.toc',1,'TOC duplicate',file,'file would load twice') end
        listed[file]=true
        if not loaded[file] then assert(loadfile('WaypointTracker/'..file))('WaypointTracker',ns);loaded[file]=true end
    end
end
toc:close()
M.FireEvent('ADDON_LOADED','WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
for i=1,3 do
    M.FireEvent('PLAYER_ENTERING_WORLD')
    ns.Window.Show('waypoints');ns.Window.Hide()
    ns.Window.Show('routes');ns.Window.Hide()
    ns.Window.Show('find');ns.Window.Hide()
end
for _,err in ipairs(M.errors) do bad('WaypointTracker',1,'lifecycle runtime error',err,'test must exercise startup without errors') end
print(('Registration audit: %d subscriptions observed; %d failures'):format(registrations,problems))
os.exit(problems==0 and 0 or 1)
