local M = {}
local config = require 'audiobookshelf.config'

local state = {
  cache_prefix = 'audiobookshelf:',
  cache_version = 0,
  cache = {},
  config_key = nil,
}

local function encode_query(params)
  local chunks = {}
  for key, value in pairs(params or {}) do
    if value ~= nil and value ~= '' then table.insert(chunks, deck.url.encode(key) .. '=' .. deck.url.encode(value)) end
  end
  table.sort(chunks)
  return table.concat(chunks, '&')
end

local function current_cfg() return config.get() end

local function config_key(cfg)
  return encode_query { url = cfg.base_url or '', token = cfg.token or '', library_id = cfg.library_id or '' }
end

local function ensure_cache_state()
  local cfg = current_cfg()
  local next_key = config_key(cfg)
  if state.config_key == next_key then return cfg end

  state.config_key = next_key
  state.cache_prefix = 'audiobookshelf:' .. next_key .. ':'
  state.cache_version = 0
  state.cache = {}
  return cfg
end

local function ensure_configured()
  local cfg = ensure_cache_state()
  if not cfg.base_url or cfg.base_url == '' then return nil, 'missing Audiobookshelf url' end
  if not cfg.token or cfg.token == '' then return nil, 'missing Audiobookshelf token' end
  return true
end

local function headers()
  local cfg = ensure_cache_state()
  return {
    Authorization = 'Bearer ' .. tostring(cfg.token or ''),
    ['Content-Type'] = 'application/json',
  }
end

local function absolute_url(path, params)
  local cfg = ensure_cache_state()
  local url = cfg.base_url .. path
  local query = encode_query(params)
  if query ~= '' then url = url .. '?' .. query end
  return url
end

local function request_json(method, path, params, body, cb)
  local ok, err = ensure_configured()
  if not ok then
    cb(nil, err)
    return
  end

  deck.http.request({
    url = absolute_url(path, params),
    method = method,
    headers = headers(),
    body = body and deck.json.encode(body) or nil,
  }, function(response)
    if not response.success then
      cb(nil, response.error or ('HTTP ' .. tostring(response.status)))
      return
    end
    if response.status < 200 or response.status >= 300 then
      cb(nil, 'HTTP ' .. tostring(response.status) .. ': ' .. tostring(response.body or ''))
      return
    end
    if not response.body or response.body == '' then
      cb(true)
      return
    end

    local decode_ok, decoded = pcall(deck.json.decode, response.body)
    if not decode_ok then
      cb(nil, 'failed to decode Audiobookshelf response')
      return
    end
    cb(decoded)
  end)
end

local function make_cache_key(name, params)
  return state.cache_prefix .. state.cache_version .. ':' .. name .. ':' .. encode_query(params)
end

local function get_cached_json(name, params, loader, cb)
  local key = make_cache_key(name, params)
  local cached = state.cache[key]
  if cached ~= nil then
    cb(cached)
    return
  end

  loader(function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    state.cache[key] = payload
    cb(payload)
  end)
end

local function selected_library_filter(libraries)
  local cfg = ensure_cache_state()
  local selected = cfg.library_id
  local out = {}
  for _, library in ipairs(libraries or {}) do
    if library.mediaType == 'book' and (not selected or selected == '' or tostring(library.id) == tostring(selected)) then
      table.insert(out, library)
    end
  end
  return out
end

function M.ensure_configured() return ensure_configured() end

function M.invalidate_cache()
  state.cache_version = state.cache_version + 1
  state.cache = {}
end

function M.media_url(path)
  local cfg = ensure_cache_state()
  if not path or path == '' then return nil end
  local url = tostring(path):match '^https?://' and tostring(path) or (cfg.base_url .. tostring(path))
  if cfg.token and cfg.token ~= '' then
    local sep = url:find('?', 1, true) and '&' or '?'
    url = url .. sep .. 'token=' .. deck.url.encode(cfg.token)
  end
  return url
end

function M.list_libraries(cb)
  get_cached_json('libraries', {}, function(done)
    request_json('GET', '/api/libraries', {}, nil, done)
  end, function(payload, err)
    if err then return cb(nil, err) end
    cb((payload or {}).libraries or {})
  end)
end

function M.list_book_libraries(cb)
  M.list_libraries(function(libraries, err)
    if err then return cb(nil, err) end
    cb(selected_library_filter(libraries))
  end)
end

function M.list_library_items(library_id, cb)
  local cfg = ensure_cache_state()
  local params = {
    sort = cfg.items_sort or 'media.metadata.title',
    limit = cfg.items_limit or 0,
    page = 0,
  }
  get_cached_json('library_items', deck.tbl_extend('force', { library_id = library_id }, params), function(done)
    request_json('GET', '/api/libraries/' .. deck.url.encode(library_id) .. '/items', params, nil, done)
  end, function(payload, err)
    if err then return cb(nil, err) end
    cb((payload or {}).results or {})
  end)
end

function M.list_all_book_items(cb)
  M.list_book_libraries(function(libraries, err)
    if err then return cb(nil, err) end
    local remaining = #libraries
    local out = {}
    if remaining == 0 then return cb(out) end

    local done_called = false
    for _, library in ipairs(libraries) do
      M.list_library_items(library.id, function(items, item_err)
        if done_called then return end
        if item_err then
          done_called = true
          cb(nil, item_err)
          return
        end
        for _, item in ipairs(items or {}) do
          item._library = library
          table.insert(out, item)
        end
        remaining = remaining - 1
        if remaining == 0 then cb(out) end
      end)
    end
  end)
end

function M.get_library(library_id, cb)
  get_cached_json('library', { id = library_id, include = 'filterdata' }, function(done)
    request_json('GET', '/api/libraries/' .. deck.url.encode(library_id), { include = 'filterdata' }, nil, done)
  end, cb)
end

function M.get_item(item_id, cb)
  get_cached_json('item', { id = item_id }, function(done)
    request_json('GET', '/api/items/' .. deck.url.encode(item_id), { expanded = 1, include = 'progress,authors' }, nil, done)
  end, cb)
end

function M.get_author(author_id, cb)
  get_cached_json('author', { id = author_id }, function(done)
    request_json('GET', '/api/authors/' .. deck.url.encode(author_id), { include = 'items,series' }, nil, done)
  end, cb)
end

function M.start_play(item_id, episode_id, cb)
  local path = '/api/items/' .. deck.url.encode(item_id) .. '/play'
  if episode_id and episode_id ~= '' then path = path .. '/' .. deck.url.encode(episode_id) end
  request_json('POST', path, {}, {
    mediaPlayer = 'lazydeck-mpv',
    forceDirectPlay = true,
    supportedMimeTypes = { 'audio/flac', 'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/opus', 'audio/webm' },
    deviceInfo = {
      clientName = 'lazydeck',
      clientVersion = '0.1.0',
    },
  }, cb)
end

return M
