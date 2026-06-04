local logger = require("logger")
local millennium = require("millennium")

local ffi = require("ffi")

ffi.cdef[[
typedef int BOOL;
typedef unsigned long DWORD;
typedef long LONG;
typedef unsigned long ULONG;
typedef void* HANDLE;
typedef void* HWND;
typedef const wchar_t* LPCWSTR;
typedef wchar_t WCHAR;
// Kitsune fix: upstream used `unsigned long` for ULONG_PTR which is 4 bytes on Windows
// (LLP64 model). The real ULONG_PTR / LONG_PTR are pointer-sized = 8 bytes on x64.
// With the wrong size, PROCESSENTRY32W ends up 12 bytes too small, so dwSize doesn't
// match what Process32FirstW expects and the call silently fails (returns 0).
typedef uintptr_t ULONG_PTR;
typedef intptr_t LONG_PTR;
typedef LONG_PTR LPARAM;
typedef unsigned int UINT;
typedef long HRESULT;
typedef int INT;
// Kitsune fix #2: SIZE_T is pointer-sized (= ULONG_PTR) — 8 bytes on x64, not 4.
// Upstream declared it as `unsigned long` (4 bytes) which made WINDOWCOMPOSITIONATTRIBDATA
// 4 bytes too small. Older Windows versions tolerated the mismatch silently; newer ones
// (post KB5089549, May 2026) validate stricter and crash the process with ACCESS_VIOLATION
// (0xC0000005) when ulDataSize is read as garbage.
typedef uintptr_t SIZE_T;
typedef char CHAR;
typedef CHAR *LPSTR;

HANDLE CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID);
BOOL Process32FirstW(HANDLE hSnapshot, void* lppe);
BOOL Process32NextW(HANDLE hSnapshot, void* lppe);
BOOL CloseHandle(HANDLE hObject);

typedef struct {
    DWORD dwSize;
    DWORD cntUsage;
    DWORD th32ProcessID;
    ULONG_PTR th32DefaultHeapID;
    DWORD th32ModuleID;
    DWORD cntThreads;
    DWORD th32ParentProcessID;
    LONG pcPriClassBase;
    DWORD dwFlags;
    WCHAR szExeFile[260];
} PROCESSENTRY32W;

static const int TH32CS_SNAPPROCESS = 0x00000002;

// Kitsune fix #3: avoid FFI callbacks entirely.
// Two minidumps from the previous implementation crashed at the EXACT same instruction
// inside millennium.luavm64.exe (offset 0x789EF) reading NULL+0x91 — a deterministic null
// deref inside the Lua VM, triggered by our use of EnumWindows with an FFI callback that
// re-enters Lua. Walk top-level windows with GetTopWindow + GetWindow(GW_HWNDNEXT)
// instead — pure Lua loop, no callback. No re-entry, no callback lifetime concerns.
HWND GetTopWindow(HWND hWndParent);
HWND GetWindow(HWND hWnd, UINT uCmd);
DWORD GetWindowThreadProcessId(HWND hWnd, DWORD* lpdwProcessId);
BOOL IsWindow(HWND hWnd);
int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, const WCHAR *lpWideCharStr, int cchWideChar, char *lpMultiByteStr, int cbMultiByte, const char *lpDefaultChar, int *lpUsedDefaultChar);
HRESULT DwmSetWindowAttribute(HWND hwnd, DWORD dwAttribute, void* pvAttribute, DWORD cbAttribute);

typedef enum _WINDOWCOMPOSITIONATTRIB {
    WCA_ACCENT_POLICY = 19
} WINDOWCOMPOSITIONATTRIB;

typedef struct _ACCENTPOLICY {
    INT nAccentState;
    INT nFlags;
    DWORD nColor;
    INT nAnimationId;
} ACCENTPOLICY;

typedef struct _WINDOWCOMPOSITIONATTRIBDATA {
    WINDOWCOMPOSITIONATTRIB nAttribute;
    void* pData;
    SIZE_T ulDataSize;
} WINDOWCOMPOSITIONATTRIBDATA;

BOOL SetWindowCompositionAttribute(HWND hWnd, WINDOWCOMPOSITIONATTRIBDATA* data);
]]

local C = ffi.C
local user32 = ffi.load("user32")
local dwmapi = ffi.load("dwmapi")

local CP_UTF8 = 65001
local TH32CS_SNAPPROCESS = 0x00000002
local WCA_ACCENT_POLICY = 19
local ACCENT_ENABLE_BLURBEHIND = 3
local ACCENT_FLAG_ENABLE_BLURBEHIND = 0x20
local DWMWA_WINDOW_CORNER_PREFERENCE = 33
local DWMWCP_ROUND = 2

local IS_CORNER_PREFERENCE_COMPATIBLE = true
local IS_BLUR_BEHIND_COMPATIBLE = true

local GW_HWNDNEXT = 2

-- Throttle: never run PatchAllWindows more than once every PATCH_THROTTLE_MS.
local last_patch_time = 0
local PATCH_THROTTLE_MS = 3000

-- Hard cap on window iteration. Desktop Z-order is typically <1k top-level windows;
-- 10k is a safety net against any future Win11 weirdness producing a cyclic list.
local MAX_WINDOW_ITER = 10000

-- cast wchar to utf8 string. 
-- 260 == MAX_PATH, we assume steam is not running from a path longer than that.
-- that is likely a safe assumption (I hope).
local function wchar_to_utf8(wstr)
    local outbuf = ffi.new("char[260]")
    local res = C.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, outbuf, 260, nil, nil)
    if res == 0 then return nil end
    return ffi.string(outbuf)
end

-- find all process IDs matching the given executable name (case insensitive)
local function find_pids_by_name(exe_name)
    local pids = {}
    local snap = C.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snap == ffi.cast("HANDLE", -1) then
        logger:error("CreateToolhelp32Snapshot failed")
        return pids
    end
    local success, result = pcall(function()
        local entry = ffi.new("PROCESSENTRY32W")
        entry.dwSize = ffi.sizeof(entry)

        local ok = C.Process32FirstW(snap, entry)
        while ok ~= 0 do
            local name = wchar_to_utf8(entry.szExeFile)
            if name then
                if name:lower() == exe_name:lower() then
                    table.insert(pids, tonumber(entry.th32ProcessID))
                end
            end
            ok = C.Process32NextW(snap, entry)
        end
        return pids
    end)
    C.CloseHandle(snap) -- Always cleanup handle
    if not success then
        logger:error("Error during process enumeration: " .. tostring(result))
        return {}
    end
    return result
end

local function EnableBlurBehind(hwnd)
    local policy = ffi.new("ACCENTPOLICY")
    policy.nAccentState = 4
    policy.nFlags = ACCENT_FLAG_ENABLE_BLURBEHIND
    policy.nColor = 0x00000000
    policy.nAnimationId = 0

    local data = ffi.new("WINDOWCOMPOSITIONATTRIBDATA")
    data.nAttribute = WCA_ACCENT_POLICY
    data.pData = ffi.cast("void*", ffi.cast("ACCENTPOLICY*", policy))
    data.ulDataSize = ffi.sizeof(policy)

    local ok
    local s, fn = pcall(function() return user32.SetWindowCompositionAttribute end)
    if s and fn ~= nil then
        ok = fn(hwnd, data)
    else
        ok = C.SetWindowCompositionAttribute(hwnd, data)
    end
    return ok ~= 0
end

local function EnableRoundedCorners(hwnd)
    local pref = ffi.new("int[1]", DWMWCP_ROUND)
    local hr = dwmapi.DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, pref, ffi.sizeof(pref))
    return hr == 0
end

local function PatchWindowContext(hwnd)
    if IS_CORNER_PREFERENCE_COMPATIBLE then
        local ok = EnableRoundedCorners(hwnd)
        if not ok then logger:error("EnableRoundedCorners failed") end
    end
    if IS_BLUR_BEHIND_COMPATIBLE then
        local ok = EnableBlurBehind(hwnd)
        if not ok then logger:error("EnableBlurBehind failed") end
    end
end

-- Get the PID owning a given top-level window. Returns 0 on error/invalid.
local function pid_of(hwnd)
    if hwnd == nil then return 0 end
    -- IsWindow returns BOOL; treat 0 as invalid.
    if user32.IsWindow(hwnd) == 0 then return 0 end
    local out = ffi.new("DWORD[1]")
    local tid = C.GetWindowThreadProcessId(hwnd, out)
    if tid == 0 then return 0 end
    return tonumber(out[0]) or 0
end

function PatchAllWindows()
    local now = os.clock() * 1000
    if (now - last_patch_time) < PATCH_THROTTLE_MS then return false end
    last_patch_time = now

    local targets = find_pids_by_name("steamwebhelper.exe")
    if #targets == 0 then
        logger:info("[PatchAllWindows] No steamwebhelper.exe processes found.")
        return false
    end

    -- Build a O(1) PID lookup table.
    local target_set = {}
    for _, pid in ipairs(targets) do target_set[pid] = true end

    -- Walk top-level windows in Z-order using GetTopWindow + GetWindow(GW_HWNDNEXT).
    -- This is a pure Lua loop calling Win32 functions one at a time — no FFI callback,
    -- no re-entrant Lua-from-C. Avoids the millennium.luavm64.exe crash at offset 0x789EF.
    local hwnd = user32.GetTopWindow(nil)
    local visited = 0
    local patched = 0

    while hwnd ~= nil and visited < MAX_WINDOW_ITER do
        visited = visited + 1
        local pid = pid_of(hwnd)
        if pid ~= 0 and target_set[pid] then
            local ok, err = pcall(PatchWindowContext, hwnd)
            if ok then
                patched = patched + 1
            else
                logger:error(string.format("[PatchAllWindows] Patch failed: %s", tostring(err)))
            end
        end
        hwnd = user32.GetWindow(hwnd, GW_HWNDNEXT)
    end

    if visited >= MAX_WINDOW_ITER then
        logger:error(string.format("[PatchAllWindows] Hit MAX_WINDOW_ITER (%d) — Z-order walk truncated.", MAX_WINDOW_ITER))
    end

    return true
end

local function on_load()
    print("Example plugin loaded")
    logger:info("Example plugin loaded with Millennium version " .. millennium.version())
    millennium.ready()
end

local function on_unload()
    logger:info("Plugin unloaded")
end

local function on_frontend_loaded()
    logger:info("Frontend loaded")
    -- Kitsune fix: upstream left a placeholder "classname.method" call here that errors.
    -- Replace it with actual patching of all current steamwebhelper.exe windows so the
    -- main Steam window (created natively before the JS hook installs) also gets transparent.
    PatchAllWindows()
end

return {
    on_frontend_loaded = on_frontend_loaded,
    on_load = on_load,
    on_unload = on_unload
}