# audiobookshelf.lazydeck

Audiobookshelf provider for `music.lazydeck`.

## Features

- Browse Audiobookshelf audiobooks through the generic `music.lazydeck` browser
- Sections provided by `music.lazydeck`:
  - `Albums`: all audiobooks from configured book libraries
  - `Artists`: authors from library filter data
  - `Search`: local title/author/narrator/series search across loaded library items
  - `Libraries`: Audiobookshelf-specific library browser via `extra_sections`
- Play audiobook audio tracks through the shared `/music` mpv queue

## Configuration

Declare `music.lazydeck` before this plugin:

```lua
{
  'urie96/music.lazydeck',
},
{
  dir = 'plugins/audiobookshelf.lazydeck',
  config = function()
    require('audiobookshelf').setup {
      url = os.getenv 'AUDIOBOOKSHELF_URL',
      token = os.getenv 'AUDIOBOOKSHELF_TOKEN',
      -- optional: restrict to one library
      library_id = os.getenv 'AUDIOBOOKSHELF_LIBRARY_ID',
    }
  end,
}
```

Environment variables:

- `AUDIOBOOKSHELF_URL`: server base URL, e.g. `https://abs.example.com`
- `AUDIOBOOKSHELF_TOKEN`: API token / bearer token
- `AUDIOBOOKSHELF_LIBRARY_ID`: optional book library id

## Implemented music provider interfaces

```lua
provider.name = 'audiobookshelf'
provider.title = 'Audiobookshelf'
provider.get_play_url(track, cb)

provider.get_albums(cb)
provider.get_album_tracks(album_id, cb)

provider.get_artists(cb)
provider.get_artist_albums(artist_id, cb)

provider.search(query, cb)
provider.extra_sections -- Libraries
```

## Notes

Audiobookshelf library items are mapped to `music` albums, and each audio track in a library item is mapped to a `music` track. Playback URLs are generated from Audiobookshelf media `contentUrl` values with the configured token appended as a query parameter.
