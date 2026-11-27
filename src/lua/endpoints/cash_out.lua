-- src/lua/endpoints/cash_out.lua

-- ==========================================================================
-- CashOut Endpoint Params
-- ==========================================================================

---@class Request.Endpoint.CashOut.Params

-- ==========================================================================
-- CashOut Endpoint
-- ==========================================================================

---@type Endpoint
return {

  name = "cash_out",

  description = "Cash out and collect round rewards",

  schema = {},

  requires_state = { G.STATES.ROUND_EVAL },

  ---@param _ Request.Endpoint.CashOut.Params
  ---@param send_response fun(response: Response.Endpoint)
  execute = function(_, send_response)
    sendDebugMessage("Init cash_out()", "BB.ENDPOINTS")
    -- Let every round-evaluation row event finish before removing
    -- G.round_eval; cashing out mid-animation leaves pending row callbacks
    -- that index a nil G.round_eval and crash the game.
    G.E_MANAGER:add_event(Event({
      trigger = "after",
      delay = 1.2,
      func = function()
        if G.STATE == G.STATES.ROUND_EVAL and G.round_eval then
          G.FUNCS.cash_out({ config = {} })
        end
        return true
      end,
    }))

    -- Wait for SHOP state after state transition completes. Do not wait for
    -- purchasable items: a fully bought-out or empty shop is still a valid
    -- stop point, and requiring items made the endpoint hang there.
    G.E_MANAGER:add_event(Event({
      trigger = "condition",
      blocking = false,
      func = function()
        if G.STATE == G.STATES.SHOP and G.STATE_COMPLETE then
          sendDebugMessage("Return cash_out() - reached SHOP state", "BB.ENDPOINTS")
          send_response(BB_GAMESTATE.get_gamestate())
          return true
        end
        return false
      end,
    }))
  end,
}
