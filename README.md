# DropShelf

DropShelf is a small Mac menu bar app for collecting files from different folders. Drag them into another app, move them together, or share them with AirDrop.

## Disclosures

- Inspired by [Dropover](https://dropoverapp.com/). If you want something much more polished and feature-complete, I'd encourage you to go for Dropover if you can spare a few dollars.
- DropShelf is free and open source under the [MIT license](LICENSE). No tracking, monetization, or premium features of any kind.
- This project serves a simple purpose and will NOT be actively maintained. Feel free to tweak the source code to your liking.
- Most of the code was written by AI, with a manual review for critical issues. Nothing is guaranteed, so please do your due diligence.
- The app was tested on an Apple Silicon Mac - Intel support is not guaranteed.

## Install

1. Download **DropShelf-1.0.4-arm64.dmg**.
2. Open it and drag **DropShelf** onto **Applications**.
3. Open DropShelf from Applications. Look for its menu bar icon; it has no Dock icon.

The app isn't Developer ID signed or notarized, so macOS may block it on first launch. After trying to open it, go to **System Settings → Privacy & Security → Open Anyway** and confirm.

## Collect files

- **From Finder:** drag one or more files, shake them horizontally, then drop onto the target in the center of the screen.
- **From the menu bar:** choose **New Shelf**, then drop files onto it.
- **From the clipboard:** copy files, then choose **Add From Clipboard** in the shelf's arrow menu.

You can disable the shake gesture with **Show drop zones when dragging files** in Settings.

## Use a shelf

- Drag the compact stack to carry every file together. Click the file count to expand it.
- Click items to select them. Use **Command-click** to toggle selection, **Shift-click** for a range, and **Command-A** to select all.
- Press **Space** for Quick Look. Right-click to open, reveal in Finder, copy, or remove an item.
- The arrow menu offers sharing, copying, moving, grid/list view, and pinning. Actions use selected items, or all items if nothing is selected.
- Drag files or folders into Finder to move them on the same drive. Hold **Option** to copy or **Command** to request a move across drives. **Move to…** moves the originals without overwriting existing files.

## Gotchas

- Shelves reference files in their original locations. Removing items or closing a shelf doesn't delete them. Moving files changes their location.
- **Pin shelves you want to keep across launches.** Up to five recently closed unpinned shelves can be reopened during the current session.