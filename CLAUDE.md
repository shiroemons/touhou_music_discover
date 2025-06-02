# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

touhou_music_discover (東方同人音楽流通) is a Rails application that tracks and manages Touhou doujin music across multiple streaming platforms (Spotify, Apple Music, YouTube Music, LINE MUSIC). It provides a unified database of albums and tracks with platform-specific metadata.

## Key Architecture

### Core Models & Relationships
- **Album** (JAN code) → has many **Track** (ISRC code)
- Platform-specific models (SpotifyAlbum, AppleMusicAlbum, etc.) link to core Album/Track
- **Original** → **OriginalSong** → **TracksOriginalSong** → **Track** (tracks Touhou game origins)
- **Circle** (doujin groups) ← **CirclesAlbum** → **Album**

### Admin Interface
Uses Avo framework at `/avo` for data management with custom actions for:
- Fetching data from streaming platforms
- Bulk operations
- Data export/import

## Common Development Commands

### Setup & Development
```bash
make init          # Initial setup with Docker
make server        # Start Rails server (http://localhost:3000)
make console       # Rails console
make bash          # Enter Docker container
```

### Database Operations
```bash
make migrate       # Run migrations
make dbseed        # Seed master data (originals, circles, artists)
```

### Testing & Code Quality
```bash
make minitest      # Run tests
make rubocop       # Run linter
```

### Platform Data Collection
Each platform has specific rake tasks for data fetching:
- `spotify:fetch_touhou_albums` - Fetch albums from "東方同人音楽流通" label
- `apple_music:fetch_artist_albums` - Fetch by artist ID
- `ytmusic:search_albums_and_save` - Search and save albums
- `line_music:search_albums_and_save` - Search and save albums

Run tasks with: `docker compose run --rm web bin/rails [task_name]`

## API Integration Notes

### Spotify
- Uses OAuth authentication via `rspotify` gem
- Fetches audio features (tempo, energy, etc.)
- Primary source: "東方同人音楽流通" label

### Apple Music
- Requires: secret_key, team_id, music_id in credentials
- Custom client implementation in `app/models/apple_music_client/`

### YouTube Music & LINE MUSIC
- Custom implementations without official gems
- Located in `lib/ytmusic/` and `lib/line_music/`

## Linting
- Uses Rubocop for Ruby code style
- Configuration follows standard Rails conventions
- Run `make rubocop` to check for issues
- Use `make rubocop-autocorrect` for auto-corrections

## Key Workflows

1. **Adding New Albums**: Use Avo actions to fetch from platforms, then associate with circles and original songs
2. **Data Export**: Use rake tasks for Algolia search or random selection app exports
3. **Platform Updates**: Each platform has separate update actions in Avo to refresh metadata

## Important Conventions

- All platform-specific models must link to core Album/Track models
- Use UUIDs for primary keys
- JAN codes identify albums, ISRC codes identify tracks
- Touhou flag (`is_touhou`) determines if content is actually Touhou-related
- Use Avo actions for all data fetching operations to maintain consistency

## Development Workflow
When making code modifications:
1. Create a new branch before making changes (if on main branch)
2. Make your modifications
3. Commit your changes with a descriptive message in Japanese
4. Push to remote repository
5. Create a Pull Request for review in Japanese

This workflow ensures code changes are properly reviewed and tracked through version control.

### Git Commit and Pull Request Guidelines
- **Commit messages**: Must be written in Japanese
- **Pull Request titles and descriptions**: Must be written in Japanese
- **Branch naming**: Use descriptive English branch names (e.g., `feature/add-feature-name`, `fix/bug-description`)

Example commit message format:
```
機能: ユーザー認証システムを追加

- JWTトークンによる認証を実装
- ログイン/ログアウトAPIを追加
- セッション管理機能を追加
```