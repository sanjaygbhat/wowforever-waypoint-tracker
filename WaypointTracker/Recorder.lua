-- The recording toolbar is a HUD system; only Edit Mode moves it.
local _, ns = ...
local L, Widgets = ns.L, ns.Widgets
local Recorder = {}
ns.Recorder = Recorder
local previousRecording

local function Preview()
    return ns.EditMode and ns.EditMode.IsActive and ns.EditMode.IsActive()
end

local function Position()
    if ns.EditMode and ns.EditMode.ApplyPosition then
        ns.EditMode.ApplyPosition("recorder")
    else
        Recorder.frame:ClearAllPoints()
        Recorder.frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function Create()
    local ok, frame = pcall(CreateFrame, "Frame", "WaypointTrackerRouteRecorder", UIParent, "BackdropTemplate")
    if not ok then frame = CreateFrame("Frame", "WaypointTrackerRouteRecorder", UIParent) end
    Recorder.frame = frame
    frame:SetSize(430, 78)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop(Widgets.BACKDROP_BOX)
        frame:SetBackdropColor(0, 0, 0, 0.9)
    end
    frame.dot = frame:CreateTexture(nil, "ARTWORK")
    frame.dot:SetColorTexture(1, 0.2, 0.2, 1)
    frame.dot:SetSize(10, 10)
    frame.dot:SetPoint("TOPLEFT", 14, -15)
    frame.text = Widgets.Label(frame, "", "GameFontNormal")
    frame.text:SetPoint("LEFT", frame.dot, "RIGHT", 8, 0)
    frame.text:SetWidth(126)
    frame.text:SetWordWrap(false)
    frame.auto = Widgets.Check(frame, L.ROUTE_REC_AUTO, {
        get = function() local rec = ns.Routes and ns.Routes.Recording(); return rec and rec.auto end,
        set = function(on) if ns.Routes then ns.Routes.RecordSetAuto(on) end end,
    }, L.ROUTE_CREATE_RECORD_DESC, 230)
    frame.auto:SetPoint("TOPLEFT", 160, -6)
    frame.auto.label:SetFontObject(GameFontHighlightSmall)
    frame.auto.label:SetWordWrap(true)
    frame.auto.label:SetHeight(42)
    frame.add = Widgets.Button(frame, L.ROUTE_REC_ADD, nil, 24)
    frame.add:SetPoint("BOTTOMLEFT", 14, 8)
    frame.add:SetScript("OnClick", ns.Safe(function() if ns.Routes then ns.Routes.RecordAdd() end end))
    Widgets.Tooltip(frame.add, L.ROUTE_REC_ADD, L.ROUTE_REC_ADD_DESC)
    frame.finish = Widgets.Button(frame, L.ROUTE_REC_FINISH, nil, 24)
    frame.finish:SetPoint("LEFT", frame.add, "RIGHT", 6, 0)
    frame.finish:SetScript("OnClick", ns.Safe(function()
        local draft = ns.Routes and ns.Routes.RecordFinish()
        if draft and ns.Window and ns.RoutesUI then
            ns.Window.Show("routes")
            ns.RoutesUI.ShowEditor(draft)
        elseif not draft then
            ns.Print(L.ROUTE_REC_EMPTY, true)
        end
    end))
    frame.cancel = Widgets.Button(frame, CANCEL or L.NO, nil, 24)
    frame.cancel:SetPoint("LEFT", frame.finish, "RIGHT", 6, 0)
    frame.cancel:SetScript("OnClick", ns.Safe(function() if ns.Routes then ns.Routes.RecordCancel() end end))
end

function Recorder.Refresh()
    if not Recorder.frame then Create() end
    local rec = ns.Routes and ns.Routes.Recording()
    if rec and rec ~= previousRecording and ns.Window and ns.Window.IsShown() then
        ns.Window.Hide()
    end
    previousRecording = rec
    local frame = Recorder.frame
    frame.text:SetText(L.ROUTE_REC_HUD:format(rec and #rec.pts or 0))
    frame.auto:Refresh()
    frame.auto:SetEnabled(rec ~= nil)
    frame.add:SetEnabled(rec ~= nil)
    frame.finish:SetEnabled(rec ~= nil and #rec.pts > 0)
    frame.cancel:SetEnabled(rec ~= nil)
    frame:SetShown(rec ~= nil or Preview())
end
ns.On("ROUTE_RECORDING", Recorder.Refresh)
ns.On("LOGIN", function()
    if not Recorder.frame then Create() end
    if ns.EditMode and ns.EditMode.RegisterSystem then
        ns.EditMode.RegisterSystem {
            key = "recorder", frame = Recorder.frame, name = L.RECORDER_EDIT_NAME,
            hint = L.RECORDER_EDIT_HINT, settings = {}, defaultPoint = { "TOP", "TOP", 0, -120 },
            shouldShow = function() return true end,
            onEnter = Recorder.Refresh,
            onExit = Recorder.Refresh,
            onReset = function()
                if ns.EditMode and ns.EditMode.SavePosition then
                    ns.EditMode.SavePosition("recorder", nil)
                else
                    ns.Set("recorderPos", nil)
                end
                Position()
            end,
        }
    end
    Position()
    Recorder.Refresh()
end)
