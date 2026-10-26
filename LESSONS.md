# Lessons learned

These notes come from recovering about 1 TB from a 2 TB My Book Live onto a Mac running macOS 15.

## About the drive

1. **The data is plain ext4 with no encryption and no proprietary format.** The tricky part is the **64 KB block size**. Mac ext4 drivers and FUSE tools generally assume 4 KB blocks, which is why they fail on these drives even though the file system is otherwise standard.
2. **The partition layout is predictable.** There are two small `Linux_RAID` partitions (the device's operating system), a small swap partition and one big data partition. The biggest partition is always the one you want.
3. **Your files live under `/shares`.** `cache` holds internal data such as media-server thumbnails. `backup` was empty on our drive, but check yours. Hidden items like `.mediacrawler` and `.tickle` are the device's own clutter and can be deleted after the copy.
4. **Time Machine backups may be inside.** A `TimeMachine` share can take up a large part of the drive. Decide whether you still need those old backups before you spend hours copying them.

## About the tools

5. **`debugfs` is the right tool for this.** It's read-only by default, it doesn't depend on any Mac file-system driver, and its `rdump` command copies a whole folder tree in one go.
6. **Building from source avoids package-manager trouble.** On shared Macs, Homebrew often belongs to another admin and fails with confusing errors. `e2fsprogs` builds in a few minutes using only Apple's command-line tools.
7. **Reading the raw disk needs `sudo`, and that can't be automated around.** Whoever runs the copy must be able to type an admin password. Plan for this when you're helping someone remotely.

## About the copy

8. **macOS treats `Photos` and `photos` as the same name, and that silently loses data.** On Linux they're two separate folders. During the copy the second one fails with `File exists` and **its contents are skipped**. Always save the copy's output to a log and search it for `File exists` afterwards.
9. **`rdump` can't leave anything out.** To skip a folder, generate one `rdump` command per item and run the list with `debugfs -f`. Showing the generated list before running it makes it easy to check.
10. **Copied files belong to `root`.** Run `chown -R` on the copy before you start tidying in Finder. Otherwise every delete or move asks for a password, or simply fails.
11. **Keep the Mac awake.** `caffeinate -i` stops a 10-hour copy from pausing when the screen locks.
12. **A progress bar that wraps is misleading.** Our first tracker printed a line wider than the Terminal window, so each update was appended instead of replacing the last one, and it was hard to tell whether the copy had finished. Keep progress lines short, clear the line before redrawing (`\r\033[K`), and check whether the copying process is still running rather than guessing from "speed: 0".
13. **Leftover processes block ejecting.** An `ls` left open in a pager (`(END)`) keeps the disk busy. Use `DEBUGFS_PAGER=__none__` for one-off commands.

## Safety habits that paid off

- **Look before copying.** Use `ls` to understand the layout and check the size, then copy.
- **Never write to the source drive.** Every step here only reads from it.
- **Keep the old drive** until you've opened files from each folder on the Mac.
- **Check before deleting duplicates.** Folders with clashing names were duplicates in our case, but that's something to confirm, not assume.
