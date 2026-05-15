local M = {}

local cfg = {
  url = os.getenv 'AUDIOBOOKSHELF_URL',
  token = os.getenv 'AUDIOBOOKSHELF_TOKEN',
  library_id = os.getenv 'AUDIOBOOKSHELF_LIBRARY_ID',
  items_sort = 'media.metadata.title',
  items_limit = 0,
  search_limit = 0,
}

local function trim(s)
  if s == nil then return nil end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function normalize(next_cfg)
  local out = next_cfg
  out.url = trim(out.url)
  out.token = trim(out.token)
  out.library_id = trim(out.library_id)

  if out.url and out.url ~= '' then
    out.base_url = out.url:gsub('/+$', '')
  else
    out.base_url = nil
  end

  out.items_limit = tonumber(out.items_limit or 0) or 0
  out.search_limit = tonumber(out.search_limit or 0) or 0
  return out
end

function M.setup(opt)
  cfg = normalize(deck.tbl_deep_extend('force', cfg, opt or {}))
end

function M.get() return cfg end

return M
