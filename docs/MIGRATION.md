# Migration from v0.2.x

**Breaking Change (v0.3.0)**: Git LFS models have been removed from the repository. Models are now downloaded at runtime via [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) to `~/Library/SharedModels/`.

- **Before v0.3.0**: Models were stored in `Models/` directory with Git LFS (~4.5 GB in repo)
- **After v0.3.0**: Models are downloaded on first use to `~/Library/SharedModels/` (~8.5 GB shared across all apps)

## Benefits

- Faster `git clone` (no LFS downloads)
- Shared model cache across multiple projects
- CI/CD caching support (models cached between runs)

## Action Required

If you have a local clone from v0.2.x or earlier, the old `Models/` directory is no longer used. You can safely delete it.
