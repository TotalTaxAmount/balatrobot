-- src/lua/endpoints/force_blind.lua

-- ==========================================================================
-- Force Blind Endpoint Params
-- ==========================================================================

---@class Request.Endpoint.ForceBlind.Params
---@field blind string "Small", "Big", or "Boss"
---@field boss string? Boss blind key for a Boss selection (e.g. bl_flint)

-- ==========================================================================
-- Force Blind Endpoint
-- ==========================================================================

---@type Endpoint
return {

  name = "force_blind",

  description = "Select Small/Big/Boss directly without granting skip tags or opening packs",

  schema = {
    blind = {
      type = "string",
      required = true,
      description = "Blind to select: Small, Big, or Boss",
    },
    boss = {
      type = "string",
      required = false,
      description = "Boss blind key for a Boss selection (e.g. bl_flint)",
    },
  },

  requires_state = { G.STATES.BLIND_SELECT },

  ---@param args Request.Endpoint.ForceBlind.Params
  ---@param send_response fun(response: Response.Endpoint)
  execute = function(args, send_response)
    sendDebugMessage("Init force_blind()", "BB.ENDPOINTS")

    local target = args.blind
    if target ~= "Small" and target ~= "Big" and target ~= "Boss" then
      send_response({
        message = "force_blind blind must be Small, Big, or Boss",
        name = BB_ERROR_NAMES.BAD_REQUEST,
      })
      return
    end

    if args.boss then
      if not G.P_BLINDS or not G.P_BLINDS[args.boss] then
        send_response({
          message = "Unknown boss blind key: " .. tostring(args.boss),
          name = BB_ERROR_NAMES.BAD_REQUEST,
        })
        return
      end
      G.GAME.round_resets.blind_choices = G.GAME.round_resets.blind_choices or {}
      G.GAME.round_resets.blind_choices.Boss = args.boss
    end

    -- Mark the preceding blinds skipped without running the skip flow, which
    -- would grant tags and can leave the client in a pack/tag state.
    local states = G.GAME.round_resets.blind_states or {}
    states.Small = "Upcoming"
    states.Big = "Upcoming"
    states.Boss = "Upcoming"
    if target == "Small" then
      states.Small = "Select"
    elseif target == "Big" then
      states.Small = "Skipped"
      states.Big = "Select"
    else
      states.Small = "Skipped"
      states.Big = "Skipped"
      states.Boss = "Select"
    end
    G.GAME.round_resets.blind_states = states
    G.GAME.round_resets.blind_tags = {}
    G.GAME.tags = {}
    G.GAME.blind_on_deck = target

    local pane = G.blind_select_opts and G.blind_select_opts[string.lower(target)]
    local select_button = pane and pane:get_UIE_by_ID("select_blind_button")
    if not select_button then
      send_response({
        message = "force_blind could not find the " .. target .. " select button",
        name = BB_ERROR_NAMES.INTERNAL_ERROR,
      })
      return
    end

    G.FUNCS.select_blind(select_button)

    G.E_MANAGER:add_event(Event({
      trigger = "condition",
      blocking = false,
      func = function()
        if G.STATE == G.STATES.SELECTING_HAND and G.hand ~= nil then
          G.GAME.round_resets.blind_states = G.GAME.round_resets.blind_states or {}
          G.GAME.round_resets.blind_states[target] = "Current"
          sendDebugMessage("Return force_blind() - " .. target, "BB.ENDPOINTS")
          send_response(BB_GAMESTATE.get_gamestate())
          return true
        end
        return false
      end,
    }))
  end,
}
