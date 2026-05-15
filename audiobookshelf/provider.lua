local M = {}

local api = require 'audiobookshelf.api'

M.name = 'audiobookshelf'
M.title = 'Audiobookshelf'

local function media(item) return (item or {}).media or {} end
local function metadata(item) return media(item).metadata or {} end

local function first_author(meta)
  if meta.authorName and meta.authorName ~= '' then return meta.authorName end
  if meta.author and meta.author ~= '' then return meta.author end
  if type(meta.authors) == 'table' and meta.authors[1] then return meta.authors[1].name or tostring(meta.authors[1]) end
  return 'Unknown author'
end

local function join_names(values)
  if type(values) ~= 'table' then return values end
  local out = {}
  for _, value in ipairs(values) do
    if type(value) == 'table' then
      table.insert(out, value.name or value.title or tostring(value.id or ''))
    else
      table.insert(out, tostring(value))
    end
  end
  return table.concat(out, ', ')
end

local function normalize_album(item, extra)
  item = item or {}
  local meta = metadata(item)
  local m = media(item)
  local out = {
    type = 'album',
    id = tostring(item.id or ''),
    name = meta.title or item.relPath or tostring(item.id or 'Audiobook'),
    artist = first_author(meta),
    year = tonumber(meta.publishedYear or 0),
    track_count = tonumber(m.numTracks or m.numAudioFiles or #(m.tracks or {}) or 0),
    duration = tonumber(m.duration or 0),
    genre = join_names(meta.genres) or '',
    source = M.name,
    raw = item,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_artist(author, extra)
  author = author or {}
  local out = {
    type = 'artist',
    id = tostring(author.id or author.name or ''),
    name = author.name or tostring(author.id or 'Author'),
    album_count = tonumber(author.numBooks or author.numItems or author.bookCount or #(author.libraryItems or {}) or 0),
    source = M.name,
    raw = author,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function track_title(track, item, index)
  local meta = metadata(item)
  return track.title
    or (track.metadata and (track.metadata.filename or track.metadata.relPath))
    or (meta.title and (meta.title .. ' #' .. tostring(index or track.index or '')))
    or tostring(track.id or track.index or 'Track')
end

local function normalize_track(track, item, extra)
  track = track or {}
  item = item or {}
  local meta = metadata(item)
  local index = tonumber(track.index or track.trackNumFromMeta or track.trackNumFromFilename or 0) or 0
  local out = {
    type = 'track',
    id = tostring(item.id or '') .. ':' .. tostring(track.id or index or track.contentUrl or track_title(track, item, index)),
    title = track_title(track, item, index),
    artist = first_author(meta),
    album = meta.title or item.relPath or tostring(item.id or ''),
    duration = tonumber(track.duration or 0),
    track_no = index,
    content_type = track.mimeType or track.codec,
    source = M.name,
    library_item_id = tostring(item.id or track.libraryItemId or ''),
    episode_id = track.episodeId,
    content_url = track.contentUrl,
    raw = track,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function tracks_from_item(item, extra)
  local m = media(item)
  local raw_tracks = m.tracks or {}
  if #raw_tracks == 0 then raw_tracks = m.audioTracks or {} end
  if #raw_tracks == 0 then raw_tracks = m.audioFiles or {} end

  local out = {}
  for i, track in ipairs(raw_tracks or {}) do
    if track.exclude ~= true then table.insert(out, normalize_track(track, item, deck.tbl_extend('force', { track_index = i }, extra or {}))) end
  end
  table.sort(out, function(a, b)
    local an = tonumber(a.track_no or a.track_index or 0) or 0
    local bn = tonumber(b.track_no or b.track_index or 0) or 0
    if an ~= bn then return an < bn end
    return tostring(a.title or '') < tostring(b.title or '')
  end)
  return out
end

local function map_items(items, mapper, extra)
  local out = {}
  for _, item in ipairs(items or {}) do
    table.insert(out, mapper(item, extra))
  end
  return out
end

local function collect_authors_from_libraries(cb)
  api.list_book_libraries(function(libraries, err)
    if err then return cb(nil, err) end
    local remaining = #libraries
    local by_id = {}
    if remaining == 0 then return cb({}) end

    local failed = false
    for _, library in ipairs(libraries) do
      api.get_library(library.id, function(payload, library_err)
        if failed then return end
        if library_err then
          failed = true
          cb(nil, library_err)
          return
        end
        local authors = ((payload or {}).filterdata or {}).authors or {}
        for _, author in ipairs(authors) do
          local id = tostring(author.id or author.name or '')
          if id ~= '' then by_id[id] = author end
        end
        remaining = remaining - 1
        if remaining == 0 then
          local out = {}
          for _, author in pairs(by_id) do
            table.insert(out, normalize_artist(author))
          end
          table.sort(out, function(a, b) return tostring(a.name or ''):lower() < tostring(b.name or ''):lower() end)
          cb(out)
        end
      end)
    end
  end)
end

function M.get_play_url(track, cb)
  if track.content_url and track.content_url ~= '' then
    cb(api.media_url(track.content_url))
    return
  end

  api.start_play(track.library_item_id or track.id, track.episode_id, function(session, err)
    if err then return cb(nil, err) end
    local audio_tracks = (session or {}).audioTracks or {}
    local target = audio_tracks[tonumber(track.track_no or track.track_index or 1) or 1] or audio_tracks[1]
    if not target or not target.contentUrl then return cb(nil, 'no playable audio track returned') end
    cb(api.media_url(target.contentUrl))
  end)
end

function M.get_albums(cb)
  api.list_all_book_items(function(items, err)
    if err then return cb(nil, err) end
    cb(map_items(items, normalize_album))
  end)
end

function M.get_album_tracks(album_id, cb)
  api.get_item(album_id, function(item, err)
    if err then return cb(nil, err) end
    cb(tracks_from_item(item, { parent = normalize_album(item), list_source = 'album' }))
  end)
end

function M.get_artists(cb)
  collect_authors_from_libraries(cb)
end

function M.get_artist_albums(artist_id, cb)
  api.get_author(artist_id, function(author, err)
    if err then return cb(nil, err) end
    cb(map_items((author or {}).libraryItems or {}, normalize_album, { parent = normalize_artist(author), list_source = 'artist' }))
  end)
end

local function matches_query(item, query)
  local q = tostring(query or ''):lower()
  if q == '' then return true end
  local meta = metadata(item)
  local haystacks = {
    meta.title,
    meta.subtitle,
    meta.authorName,
    meta.author,
    meta.narratorName,
    meta.seriesName,
    item.relPath,
    join_names(meta.genres),
  }
  for _, value in ipairs(haystacks) do
    if value and tostring(value):lower():find(q, 1, true) then return true end
  end
  return false
end

function M.search(query, cb)
  api.list_all_book_items(function(items, err)
    if err then return cb(nil, err) end

    local albums = {}
    local artists_by_name = {}
    for _, item in ipairs(items or {}) do
      if matches_query(item, query) then
        local album = normalize_album(item, { list_source = 'search', query = query })
        table.insert(albums, album)
        if album.artist and album.artist ~= '' then
          artists_by_name[album.artist] = { id = album.artist, name = album.artist, album_count = (artists_by_name[album.artist] and artists_by_name[album.artist].album_count or 0) + 1 }
        end
      end
    end

    local artists = {}
    for _, artist in pairs(artists_by_name) do
      table.insert(artists, normalize_artist(artist, { list_source = 'search', query = query }))
    end
    table.sort(albums, function(a, b) return tostring(a.name or ''):lower() < tostring(b.name or ''):lower() end)
    table.sort(artists, function(a, b) return tostring(a.name or ''):lower() < tostring(b.name or ''):lower() end)

    cb {
      tracks = {},
      albums = albums,
      artists = artists,
      playlists = {},
    }
  end)
end

M.extra_sections = {
  {
    key = 'library',
    title = 'Libraries',
    icon = '󰂺',
    description = 'Browse Audiobookshelf book libraries',
    list = function(path, cb)
      if #path == 2 then
        api.list_book_libraries(function(libraries, err)
          if err then return cb(nil, err) end
          local entries = {}
          for _, library in ipairs(libraries or {}) do
            table.insert(entries, {
              key = tostring(library.id or ''),
              kind = 'section',
              display = deck.style.line {
                deck.style.span(library.name or library.id or 'Library'):fg 'cyan',
                deck.style.span('  ·  '):fg 'dark_gray',
                deck.style.span(library.mediaType or ''):fg 'yellow',
              },
            })
          end
          if #entries == 0 then table.insert(entries, { key = 'empty', kind = 'info', display = 'No book libraries.' }) end
          cb(entries)
        end)
        return
      end

      api.list_library_items(path[3], function(items, err)
        if err then return cb(nil, err) end
        local entries = {}
        for i, album in ipairs(map_items(items, normalize_album, { list_source = 'library' })) do
          table.insert(entries, {
            key = tostring(album.id or i),
            kind = 'album',
            item = album,
            display = deck.style.line {
              deck.style.span(album.name or album.id or 'Audiobook'):fg 'yellow',
              deck.style.span('  ·  '):fg 'dark_gray',
              deck.style.span(album.artist or 'Unknown author'):fg 'cyan',
            },
            preview = function(entry, done)
              done(deck.style.text {
                deck.style.line { deck.style.span(entry.item.name or 'Audiobook'):fg('yellow'):bold() },
                deck.style.line { 'Author: ', deck.style.span(entry.item.artist or '-'):fg 'cyan' },
                deck.style.line { 'Duration: ', tostring(entry.item.duration or 0) },
              })
            end,
          })
        end
        if #entries == 0 then table.insert(entries, { key = 'empty', kind = 'info', display = 'No audiobooks.' }) end
        cb(entries)
      end)
    end,
  },
}

return M
