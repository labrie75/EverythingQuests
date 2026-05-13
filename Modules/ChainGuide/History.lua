-- Modules/ChainGuide/History.lua
-- Back/Forward navigation stack for the Chain Guide. Each entry is a small
-- view-state table the Frame can re-render. New navigation truncates the
-- forward stack (standard browser semantics).

local _, ns = ...

local H = ns:RegisterSubsystem("ChainGuideHistory", {})

H.stack  = {}
H.cursor = 0          -- index into stack of the current view (0 = empty)

function H:Push(state)
    -- Replace duplicate-of-current with itself (no-op) so the user doesn't
    -- end up with redundant entries when re-clicking the same item.
    local cur = self.stack[self.cursor]
    if cur and cur.type == state.type and cur.id == state.id then return end

    -- Truncate forward history before appending — standard browser model.
    for i = self.cursor + 1, #self.stack do self.stack[i] = nil end
    self.stack[#self.stack + 1] = state
    self.cursor = #self.stack
end

function H:Current()  return self.stack[self.cursor] end
function H:CanBack()  return self.cursor > 1 end
function H:CanForward() return self.cursor < #self.stack end

function H:Back()
    if self:CanBack() then self.cursor = self.cursor - 1 end
    return self:Current()
end

function H:Forward()
    if self:CanForward() then self.cursor = self.cursor + 1 end
    return self:Current()
end

function H:Reset()
    wipe(self.stack)
    self.cursor = 0
end
