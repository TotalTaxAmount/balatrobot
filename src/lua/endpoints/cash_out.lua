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

    local responded = false
    local cash_started = false
    local function respond()
      if responded then return end
      responded = true
      send_response(BB_GAMESTATE.get_gamestate())
    end

    -- Wait for the round-evaluation UI to finish its row/dollar callbacks
    -- before calling cash_out. Removing G.round_eval while those events are
    -- pending makes them index a nil G.round_eval and crash. Also wait for the
    -- shop after the cash-out so an empty shop cannot hang the endpoint.
    local cash_event
    cash_event = Event({
      trigger = "condition",
      blocking = false,
      created_on_pause = true,
      func = function()
        if responded then return true end
        if G.STATE ~= G.STATES.ROUND_EVAL then
          -- The user or a previous action already advanced past round eval.
          respond()
          return true
        end
        if cash_started then
          if G.STATE == G.STATES.SHOP and G.STATE_COMPLETE then
            sendDebugMessage("Return cash_out() - reached SHOP state", "BB.ENDPOINTS")
            respond()
            return true
          end
          return false
        end
        if not G.round_eval or not G.STATE_COMPLETE or G.CONTROLLER.locked then
          return false
        end
        for _, queue in pairs(G.E_MANAGER.queues) do
          for _, event in ipairs(queue) do
            if event ~= cash_event and not event.complete then
              return false
            end
          end
        end
        G.FUNCS.cash_out({ config = {} })
        cash_started = true
        return false
      end,
    })
    G.E_MANAGER:add_event(cash_event)
  end,
}
