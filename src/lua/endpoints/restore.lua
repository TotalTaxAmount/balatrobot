-- src/lua/endpoints/restore.lua

-- ==========================================================================
-- Restore Endpoint Params
-- ==========================================================================

---@class Request.Endpoint.Restore.Params
---@field ante integer? Ante number
---@field round integer? Round number
---@field score integer? Current blind score
---@field money integer? Current money
---@field hands integer? Hands remaining
---@field discards integer? Discards remaining
---@field skips integer? Skipped-blind count
---@field joker_slots integer? Joker slot limit
---@field hand_size integer? Hand size limit
---@field jokers table[]? Jokers to install, in order
---@field cards table[]? Hand cards to install, in order
---@field hand_levels table? Per-hand level/chips/mult/played values

-- ==========================================================================
-- Restore Endpoint Utils
-- ==========================================================================

local EDITION_MAP = {
  HOLO = "e_holo",
  FOIL = "e_foil",
  POLYCHROME = "e_polychrome",
  NEGATIVE = "e_negative",
}

local ENHANCEMENT_MAP = {
  BONUS = "m_bonus",
  MULT = "m_mult",
  WILD = "m_wild",
  GLASS = "m_glass",
  STEEL = "m_steel",
  STONE = "m_stone",
  GOLD = "m_gold",
  LUCKY = "m_lucky",
}

local SEAL_MAP = {
  RED = "Red",
  BLUE = "Blue",
  GOLD = "Gold",
  PURPLE = "Purple",
}

local SUIT_MAP = {
  H = "Hearts",
  D = "Diamonds",
  C = "Clubs",
  S = "Spades",
}

local RANK_MAP = {
  ["2"] = "2",
  ["3"] = "3",
  ["4"] = "4",
  ["5"] = "5",
  ["6"] = "6",
  ["7"] = "7",
  ["8"] = "8",
  ["9"] = "9",
  T = "10",
  J = "Jack",
  Q = "Queen",
  K = "King",
  A = "Ace",
}

local function merge_ability(target, source)
  for key, value in pairs(source) do
    if type(value) == "table" and type(target[key]) == "table" then
      merge_ability(target[key], value)
    else
      target[key] = value
    end
  end
end

local function clear_area(area)
  if not area or not area.cards then
    return
  end
  if area.unhighlight_all then
    area:unhighlight_all()
  end
  while #area.cards > 0 do
    local card = area.cards[#area.cards]
    if area.remove_card then
      pcall(function()
        area:remove_card(card)
      end)
    end
    if card and card.remove then
      pcall(function()
        card:remove()
      end)
    end
    -- remove_card may already have spliced the array; make sure this exact
    -- card is gone even if it only detached the UI object.
    for index = #area.cards, 1, -1 do
      if area.cards[index] == card then
        table.remove(area.cards, index)
        break
      end
    end
  end
  if area.config then
    area.config.card_count = 0
  end
end

local function set_limit(area, limit)
  if area and area.config and limit then
    area.config.card_limit = math.max(limit, 0)
  end
end

local function normalize_card(card, spec, is_playing)
  if not card then
    return
  end

  if is_playing and not spec.enhancement and card.ability then
    -- SMODS.add_card can roll a random enhancement when none is supplied.
    -- Reset plain cards to the base ability so the replay hand matches the
    -- saved state and does not accidentally score Steel/Glass/etc.
    card.ability.effect = "Base"
    card.ability.name = "Default Base"
    card.ability.set = "Default"
    card.ability.bonus = 0
    card.ability.mult = 0
    card.ability.h_chips = 0
    card.ability.h_mult = 0
    card.ability.h_x_chips = 1
    card.ability.h_x_mult = 0
    card.ability.h_dollars = 0
    card.ability.p_dollars = 0
    card.ability.x_chips = 1
    card.ability.x_mult = 1
    card.ability.t_chips = 0
    card.ability.t_mult = 0
    card.ability.d_size = 0
    card.ability.repetitions = 0
    if card.config and G.P_CENTERS and G.P_CENTERS.c_base then
      card.config.center = G.P_CENTERS.c_base
      card.config.center_key = "c_base"
    end
  end

  if spec.edition then
    local edition = {}
    edition[spec.edition:lower()] = true
    if card.set_edition then
      card:set_edition(edition, true, true)
    end
  elseif card.set_edition then
    card:set_edition(nil, true, true)
  else
    card.edition = nil
  end

  if is_playing then
    if spec.enhancement then
      local center = G.P_CENTERS and G.P_CENTERS[ENHANCEMENT_MAP[spec.enhancement]]
      -- Re-assert the enhancement on the created object. Normalization is
      -- object-based, so this can never land on a different card.
      if center and card.config and card.config.center ~= center and card.set_ability then
        card:set_ability(center, nil, true)
      end
    end
    if spec.seal then
      card.seal = SEAL_MAP[spec.seal]
    else
      card.seal = nil
    end
    if card.ability and spec.perma_bonus then
      card.ability.perma_bonus = spec.perma_bonus
    end
    card.debuff = spec.debuff or nil
  elseif card.ability then
    if spec.ability then
      merge_ability(card.ability, spec.ability)
    end
    card.ability.eternal = spec.eternal or nil
    card.ability.rental = spec.rental or nil
    if spec.perishable then
      card.ability.perish_tally = spec.perishable
    elseif card.ability.perish_tally ~= nil then
      card.ability.perish_tally = 0
    end
  end
end

local function add_spec(spec)
  local key = spec.key
  if type(key) ~= "string" then
    return false, "missing card key"
  end

  local is_playing = key:match("^[HDCS]_[2-9TJQKA]$") ~= nil
  local params
  if is_playing then
    params = {
      rank = RANK_MAP[key:sub(3, 3)],
      suit = SUIT_MAP[key:sub(1, 1)],
      skip_materialize = true,
    }
    if not params.rank or not params.suit then
      return false, "invalid playing card key " .. key
    end
    if spec.enhancement then
      params.enhancement = ENHANCEMENT_MAP[spec.enhancement]
    end
    if spec.edition then
      params.edition = EDITION_MAP[spec.edition]
    end
    if spec.seal then
      params.seal = SEAL_MAP[spec.seal]
    end
  else
    params = {
      key = key,
      skip_materialize = true,
      stickers = {},
      force_stickers = true,
    }
    if spec.edition then
      params.edition = EDITION_MAP[spec.edition]
    end
    if spec.eternal then
      table.insert(params.stickers, "eternal")
    end
    if spec.perishable then
      table.insert(params.stickers, "perishable")
    end
    if spec.rental then
      table.insert(params.stickers, "rental")
    end
  end

  local ok, result = pcall(SMODS.add_card, params)
  if not ok or not result then
    return nil, tostring(result)
  end

  if spec.id then
    result.sort_id = spec.id
    G.sort_id = math.max(G.sort_id or 0, spec.id)
  end
  normalize_card(result, spec, is_playing)
  return result
end

-- Move a freshly created card into the requested area. SMODS.add_card puts
-- playing cards in the hand; deck/discard restoration needs them elsewhere.
local function place_card(card, area)
  if not card or not area or not area.cards then
    return
  end
  if card.area and card.area ~= area and card.area.cards then
    for index = #card.area.cards, 1, -1 do
      if card.area.cards[index] == card then
        table.remove(card.area.cards, index)
        break
      end
    end
    if card.area.config then
      card.area.config.card_count = #card.area.cards
    end
  end
  for index = #area.cards, 1, -1 do
    if area.cards[index] == card then
      table.remove(area.cards, index)
    end
  end
  card.area = area
  area.cards[#area.cards + 1] = card
  if area.config then
    area.config.card_count = #area.cards
  end
end

local function install_area(area, specs, warnings, label)
  local installed = {}
  for index, spec in ipairs(specs) do
    local card, error_message = add_spec(spec)
    if card then
      place_card(card, area)
      installed[#installed + 1] = card
    else
      warnings[#warnings + 1] = label .. "[" .. (index - 1) .. "] " .. tostring(error_message)
    end
  end
  return installed
end

local function normalize_list(created, specs, is_playing)
  for index, spec in ipairs(specs) do
    normalize_card(created[index], spec, is_playing)
  end
end

-- ==========================================================================
-- Restore Endpoint
-- ==========================================================================

---@type Endpoint
return {

  name = "restore",

  description = "Replace the live hand, jokers, hand levels, and round counters from a bench replay",

  schema = {
    ante = { type = "integer", required = false, description = "Ante number" },
    round = { type = "integer", required = false, description = "Round number" },
    score = { type = "integer", required = false, description = "Current blind score" },
    money = { type = "integer", required = false, description = "Current money" },
    hands = { type = "integer", required = false, description = "Hands remaining" },
    discards = { type = "integer", required = false, description = "Discards remaining" },
    skips = { type = "integer", required = false, description = "Skipped-blind count" },
    joker_slots = { type = "integer", required = false, description = "Joker slot limit" },
    hand_size = { type = "integer", required = false, description = "Hand size limit" },
    jokers = { type = "array", required = false, items = "table", description = "Jokers to install, in order" },
    cards = { type = "array", required = false, items = "table", description = "Hand cards to install, in order" },
    deck = { type = "array", required = false, items = "table", description = "Draw pile, top card first" },
    discard = { type = "array", required = false, items = "table", description = "Discard pile, in order" },
    only_hand = { type = "string", required = false, description = "The Mouth's locked hand type" },
    hands_played = { type = "integer", required = false, description = "Hands played this round" },
    hand_levels = { type = "table", required = false, description = "Per-hand level data" },
  },

  requires_state = { G.STATES.SELECTING_HAND },

  ---@param args Request.Endpoint.Restore.Params
  ---@param send_response fun(response: Response.Endpoint)
  execute = function(args, send_response)
    sendDebugMessage("Init restore()", "BB.ENDPOINTS")

    if not G.jokers or not G.hand then
      send_response({
        message = "restore() requires a live blind with hand and joker areas",
        name = BB_ERROR_NAMES.INVALID_STATE,
      })
      return
    end

    -- A blind whose target is already met is not a playable decision state.
    -- Restoring it can race the round-evaluation UI and crash the game.
    if args.score and G.GAME.blind and (G.GAME.blind.chips or 0) > 0
      and args.score >= G.GAME.blind.chips then
      send_response({
        message = "restore() state already meets the blind target",
        name = BB_ERROR_NAMES.INVALID_STATE,
      })
      return
    end

    local jokers = args.jokers or {}
    local cards = args.cards or {}
    local deck = args.deck or {}
    local discard = args.discard or {}

    -- Limits must be raised before adding cards, especially for replay boards
    -- with more than the vanilla 5 jokers / 8 hand cards.
    local hand_limit = math.max(args.hand_size or 0, #cards, #deck + #discard, 8)
    set_limit(G.jokers, args.joker_slots or #jokers)
    set_limit(G.hand, hand_limit)
    set_limit(G.deck, math.max(#deck, 52))
    set_limit(G.discard, math.max(#discard, 52))

    clear_area(G.jokers)
    clear_area(G.consumeables)
    clear_area(G.deck)
    clear_area(G.discard)
    clear_area(G.hand)
    G.GAME.tags = {}
    G.GAME.round_resets.blind_tags = {}

    local warnings = {}
    local joker_cards = install_area(G.jokers, jokers, warnings, "joker")

    -- Hand-size jokers can trigger a refill while being added; clear whatever
    -- they dealt before installing the captured piles.
    set_limit(G.hand, hand_limit)
    clear_area(G.hand)

    -- `deck` is given top card first, while Balatro's G.deck.cards is
    -- bottom-first (the tail is drawn next), so install it reversed.
    local deck_specs = {}
    for index = #deck, 1, -1 do
      deck_specs[#deck_specs + 1] = deck[index]
    end
    local deck_cards = install_area(G.deck, deck_specs, warnings, "deck")
    local discard_cards = install_area(G.discard, discard, warnings, "discard")

    -- Installing deck/discard cards transiently puts them in the hand.
    clear_area(G.hand)
    local hand_cards = install_area(G.hand, cards, warnings, "card")

    -- Guarantee the captured order even if SMODS inserted cards elsewhere.
    G.jokers.cards = joker_cards
    G.jokers.config.card_count = #joker_cards
    G.hand.cards = hand_cards
    G.hand.config.card_count = #hand_cards
    G.deck.cards = deck_cards
    G.deck.config.card_count = #deck_cards
    G.discard.cards = discard_cards
    G.discard.config.card_count = #discard_cards
    set_limit(G.hand, args.hand_size or #cards)

    normalize_list(hand_cards, cards, true)
    normalize_list(joker_cards, jokers, false)
    normalize_list(deck_cards, deck_specs, true)
    normalize_list(discard_cards, discard, true)

    if args.hand_levels and G.GAME.hands then
      for name, level in pairs(args.hand_levels) do
        local hand = G.GAME.hands[name]
        if hand then
          hand.level = level.level or hand.level or 1
          hand.chips = level.chips or hand.chips or 0
          hand.mult = level.mult or hand.mult or 0
          hand.played = level.played or 0
          hand.played_this_round = level.played_this_round or 0
        end
      end
    end

    if args.ante then
      G.GAME.round_resets.ante = args.ante
    end
    if args.round then
      G.GAME.round = args.round
    end
    if args.score then
      G.GAME.chips = args.score
    end
    if args.money then
      G.GAME.dollars = args.money
    end
    if args.hands then
      G.GAME.current_round.hands_left = args.hands
    end
    if args.discards then
      G.GAME.current_round.discards_left = args.discards
    end
    if args.skips then
      G.GAME.skips = args.skips
    end
    G.GAME.current_round.hands_played = args.hands_played or 0
    G.GAME.current_round.discards_used = 0
    if G.GAME.blind and G.GAME.blind.name == "The Mouth" then
      G.GAME.blind.only_hand = args.only_hand or false
    end

    if #warnings > 0 then
      sendDebugMessage("restore warnings: " .. table.concat(warnings, "; "), "BB.ENDPOINTS")
    end

    G.E_MANAGER:add_event(Event({
      trigger = "condition",
      blocking = false,
      func = function()
        if G.STATE_COMPLETE and not G.CONTROLLER.locked then
          normalize_list(hand_cards, cards, true)
          normalize_list(joker_cards, jokers, false)
          normalize_list(deck_cards, deck_specs, true)
          normalize_list(discard_cards, discard, true)
          sendDebugMessage("Return restore()", "BB.ENDPOINTS")
          local state_data = BB_GAMESTATE.get_gamestate()
          if #warnings > 0 then
            state_data.restore_warnings = warnings
          end
          send_response(state_data)
          return true
        end
        return false
      end,
    }))
  end,
}
