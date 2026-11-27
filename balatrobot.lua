-- Load required files
assert(SMODS.load_file("src/lua/settings.lua"))() -- define BB_SETTINGS

-- Configure Balatro with appropriate settings from environment variables
BB_SETTINGS.setup()

-- Guard stale round-evaluation callbacks. `Game:update_round_eval` queues an
-- immediate event that keeps checking G.round_eval; cashing out (or entering
-- endless mode) can remove G.round_eval before that callback runs, which
-- crashes at `G.round_eval.alignment` / `G.round_eval.T`. Wrap only the
-- events created by that update function and complete them when the UI is
-- already gone.
if Game and Game.update_round_eval and EventManager and not Game.__bb_round_eval_guard then
  local in_round_eval_update = false
  local original_update_round_eval = Game.update_round_eval
  Game.update_round_eval = function(self, dt)
    in_round_eval_update = true
    local ok, result = pcall(original_update_round_eval, self, dt)
    in_round_eval_update = false
    if not ok then error(result) end
    return result
  end
  Game.__bb_round_eval_guard = true

  local original_add_event = EventManager.add_event
  EventManager.add_event = function(self, event, queue, front)
    if in_round_eval_update and event and event.func then
      local func = event.func
      event.func = function(...)
        if G.round_eval == nil then
          return true
        end
        return func(...)
      end
    end
    return original_add_event(self, event, queue, front)
  end
end

-- Endpoints for the BalatroBot API
BB_ENDPOINTS = {
  -- Health endpoint
  "src/lua/endpoints/health.lua",
  -- Gamestate endpoints
  "src/lua/endpoints/gamestate.lua",
  -- Save/load endpoints
  "src/lua/endpoints/save.lua",
  "src/lua/endpoints/load.lua",
  -- Screenshot endpoint
  "src/lua/endpoints/screenshot.lua",
  -- Game control endpoints
  "src/lua/endpoints/set.lua",
  "src/lua/endpoints/add.lua",
  "src/lua/endpoints/restore.lua",
  -- Gameplay endpoints
  "src/lua/endpoints/menu.lua",
  "src/lua/endpoints/start.lua",
  -- Blind selection endpoints
  "src/lua/endpoints/skip.lua",
  "src/lua/endpoints/select.lua",
  "src/lua/endpoints/force_blind.lua",
  -- Play/discard endpoints
  "src/lua/endpoints/play.lua",
  "src/lua/endpoints/discard.lua",
  -- Cash out endpoint
  "src/lua/endpoints/cash_out.lua",
  -- Shop endpoints
  "src/lua/endpoints/next_round.lua",
  "src/lua/endpoints/reroll.lua",
  "src/lua/endpoints/buy.lua",
  "src/lua/endpoints/pack.lua",
  -- Rearrange endpoint
  "src/lua/endpoints/rearrange.lua",
  -- Sell endpoint
  "src/lua/endpoints/sell.lua",
  -- Use consumable endpoint
  "src/lua/endpoints/use.lua",
  -- If debug mode is enabled, debugger.lua will load test endpoints
}

-- Enable debug mode
if BB_SETTINGS.debug then
  assert(SMODS.load_file("src/lua/utils/debugger.lua"))() -- define BB_DEBUG
  BB_DEBUG.setup()
end

-- Load core modules
assert(SMODS.load_file("src/lua/core/server.lua"))() -- define BB_SERVER
assert(SMODS.load_file("src/lua/core/dispatcher.lua"))() -- define BB_DISPATCHER

-- Load gamestate and errors utilities
BB_GAMESTATE = assert(SMODS.load_file("src/lua/utils/gamestate.lua"))()
assert(SMODS.load_file("src/lua/utils/errors.lua"))()

-- Initialize Server
local server_success = BB_SERVER.init()
if not server_success then
  return
end

local dispatcher_ok = BB_DISPATCHER.init(BB_SERVER, BB_ENDPOINTS)
if not dispatcher_ok then
  return
end

-- Hook into love.update to run server update loop and detect GAME_OVER
local love_update = love.update
love.update = function(dt) ---@diagnostic disable-line: duplicate-set-field
  -- Check for GAME_OVER before game logic runs
  BB_GAMESTATE.check_game_over()
  love_update(dt)
  BB_SERVER.update(BB_DISPATCHER)
end

sendInfoMessage("BalatroBot loaded - version " .. SMODS.current_mod.version, "BB.BALATROBOT")
