# OSS landscape scan, 30 September 2026

What comparable open-source disk analyzers and cleanup tools ship, and where each idea lands against storagedaddy's current surfaces. Purpose: pick the next build order with eyes open. Disktree (issue #33) is covered separately in the issue; this doc covers the rest of the field.

## Projects surveyed

| Project | What it is | License |
| --- | --- | --- |
| [tw93/Mole](https://github.com/tw93/Mole) (~68k★) | macOS all-in-one CLI: clean, uninstall, analyze, optimize, status, purge, installer | GPL-3.0 |
| [alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner) (~15k★) | Native Mac app cleaner: uninstall, orphans, dev environments, brew, lipo | Apache-2.0 + Commons Clause (no monetization) |
| [qarmin/czkawka](https://github.com/qarmin/czkawka) (~25k★) | Rust multi-tool: duplicates, empty/broken files, similar images, bad extensions | MIT (GUI/CLI/core) |
| [tbillington/kondo](https://github.com/tbillington/kondo) (~9k★) | Cleans `node_modules`, `target`, `build` across 20+ project types, age-filtered | MIT |
| [voidcosmos/npkill](https://github.com/voidcosmos/npkill) (~7k★) | `node_modules` locator/remover with last-workspace-activity column | MIT |
| [shundhammer/qdirstat](https://github.com/shundhammer/qdirstat) (~4k★) | Qt dir-stats: treemap, per-extension stats, file-age histogram, package views | GPL-2.0 |
| [Canop/dysk](https://github.com/Canop/dysk) (~2k★) | `df` successor: filesystems table, filters, JSON, inode view | MIT |
| [muesli/duf](https://github.com/muesli/duf) (~13k★) | `df` successor: grouped mounts, inodes, JSON | MIT |
| [tobi/disktree](https://github.com/tobi/disktree) | Omarchy treemap; covered by issue #33 | MIT |

License note: Mole is GPL — ideas only, never code. Pearcleaner is Commons Clause — approach is fair game, code is not if storagedaddy ever monetizes; treat as clean-room reference.

## What they do well that we don't

### 1. Project-grouped artifact purge (Mole `mo purge`, kondo, npkill)

Mole's purge groups rebuildable artifacts (`node_modules`, `target`, `dist`, `.build`) under their **owning project root**, shows artifact age, and pre-selects nothing that had activity in the last 7 days or anything it can't verify. Protections worth copying as a tested module:

- Skip dirs containing deployment keypair files
- Skip nested git repositories (purge the worktree's artifacts, never the worktree)
- Skip git-tracked files inside artifact dirs
- Whitelist config persists; incomplete scans are labeled, never auto-selected

npkill's contribution: `last_mod` = newest mtime anywhere in the *workspace*, so a stale project is defined by its whole checkout, not just the artifact dir's timestamp. kondo adds `--older 3M` batching and 20+ project-type signatures.

We have `DeveloperInsights` findings (node_modules, buildOutputs, pythonEnvironments…) as a flat list. Nothing groups them by project, nothing computes project-level last activity, nothing stages a whole-project reclaimable set. This is the biggest conceptual upgrade available and directly serves the PRODUCT.md thesis: "the strongest cleanup unit is the whole abandoned footprint."

### 2. Installer file finder (Mole `mo installer`)

Finds `.dmg`, `.pkg`, `.mpkg`, `.xip`, `.iso`, installer `.zip` in Downloads/Desktop/Homebrew caches/iCloud. Trivial detection, shows source location per file. We surface these today only as anonymous large files in Top Sizes. A canned "Installers" finding category is a small, high-delight addition — downloads folders grow these constantly.

### 3. Duplicate detection — already half-built

`DuplicateFinder` in `Sources/DiskCore/Analysis.swift` does size-bucketed hashing and returns `DuplicateGroup`s with wasted bytes — and nothing calls it. Dead engine. A Duplicates surface is product-in-scope (PRODUCT.md owns "duplicates") and mostly needs UI: group list, keep-one selector, reclaim estimate, then stage through the normal review/Trash path. APFS nuance to handle: cloned files share physical blocks, so "wasted" must come from allocated bytes or cloning-aware accounting, not logical bytes alone.

### 4. Orphaned app leftovers (Pearcleaner, Mole `mo clean`)

Scan `~/Library` subtrees (Application Support, Caches, Preferences, HTTPStorages, WebKit, Containers, LaunchAgents, Saved Application State) for folders whose bundle-ID prefix or app-name token matches **no installed app**. Pearcleaner's whole reputation is the accuracy of this matching (name variants, company prefixes, plist identifiers). Strong fit: we already inventory installed apps, so the reference set exists. Present as "Leftovers" findings with the app name they're attributed to — evidence-backed, never auto-selected.

### 5. File-type statistics (QDirStat)

Aggregate disk usage by extension/MIME category: "14 GB of `.dmg`, 9 GB of `.zip`, 6 GB of `.mov`". Cheap from scan metadata we already collect; gives Explore a "what kind of data is this" answer that byte-trees can't. QDirStat also puts a mini-treemap on the extension view, which pairs naturally with our map modes. Could also feed the semantic-color classifier for #33.

### 6. File-age histogram (QDirStat)

Monthly age buckets + percentile stats ("50% of files here untouched for 2+ years"). Our Age Map has 4 fixed buckets; a real histogram with selectable granularity is an upgrade to the same surface. Low effort, moderate value.

### 7. Dashboard additions (dysk, duf, Mole `mo status`)

- **Inode usage** — `statfs` `f_files`/`f_ffree`, one extra syscall per volume. Rarely a problem on APFS but free to show.
- **Live I/O rate** — we already read per-boot `IOBlockStorageDriver` counters; two samples → MB/s now. Also enables "which volume is busy".
- **Storage-health score** — Mole composes CPU/RAM/disk/SMART into one number; we should keep it storage-scoped (free %, purgeable %, wear %, snapshot count) to respect the PerformanceDaddy ownership boundary.

### 8. Cleanup operations log (Mole `mo history`)

Persisted log of what was staged/trashed/emptied and estimated freed bytes, viewable as JSON. We have `SnapshotHistoryStore` for scans but no comparable *cleanup* audit trail. Fits inside History.

### 9. Whitelist / protected-path config (Mole)

Persistent "never suggest this" list for cleanup findings — separate from scan exclusions (which hide data entirely). We have excluded folders; a cleanup-only protection list is a smaller, safer hammer.

### 10. Misc cheap wins

- **Old Downloads (90d+)** as a Mole-style analyze category — one filter over existing metadata.
- **Empty folders** and **broken symlinks** (czkawka) — nearly free from scan data; symlink inventory already exists in `FolderSymlinks`.
- **Homebrew cache/manager** (Pearcleaner) — `~/Library/Caches/Homebrew` is often multi-GB; a brew-specific finding would fit Developer Insights without becoming a package manager.
- **Finder extension** (Pearcleaner) — right-click "Reveal in storagedaddy" / "Stage for cleanup". Nice, medium effort.

## What we should skip or defer

- **Similar images/videos** (czkawka perceptual hashing) — weeks of work, weak developer-first fit.
- **System optimization tasks** (Mole `mo optimize` — DNS flush, Spotlight rebuild, icon caches) — drifts toward CleanMyMac; away from "explain storage" identity.
- **Live CPU/GPU/process monitoring** (Mole `mo status`) — PerformanceDaddy territory per PRODUCT.md; keep the dashboard storage-scoped.
- **App lipo / translation pruning** (Pearcleaner) — mutates installed app bundles; high risk, off-mission.
- **Sentinel trash watcher** (Pearcleaner) — background monitor contradicts "launched-when-needed, read-heavy" posture.
- **WizTree-style instant scan via Spotlight index** — MFT equivalent doesn't exist on macOS; MDQuery misses non-indexed dirs and can't replace the scanner. Not worth a second-class scan path.

## Suggested build order

1. **Duplicates surface** — engine exists and is uncalled; biggest user-visible feature per unit of work.
2. **Project purge** — project-grouped artifacts + whole-workspace last-activity + Mole-style protections; upgrades Developer Insights from list to workflow.
3. **Installers + Old Downloads + Leftovers** — one "Findings expansion" issue; all are canned categories over existing metadata.
4. **File-type stats + age histogram** — Explore enrichment, pairs with #33's semantic colors.
5. **Dashboard round 2** — inodes, live I/O rate, storage-health score.
6. **Cleanup history + cleanup whitelist** — trust features, small diffs.

Issue #33 (disktree map upgrades) remains its own track — most of the above are orthogonal surfaces, not map work.
