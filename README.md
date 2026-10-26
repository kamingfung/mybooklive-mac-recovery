# Rescue files from a WD My Book Live on a Mac

The WD My Book Live is end-of-life, and Western Digital told owners to unplug it. If yours still holds old photos, music or documents, you can take the hard drive out of the enclosure, connect it to a Mac with a SATA-to-USB adapter or dock, and copy everything off.

macOS can't open the drive because it uses a Linux file system (ext4). This guide shows how to read it anyway with `debugfs`, a free, read-only tool from the Linux `e2fsprogs` project. You don't need extra paid software, kernel extensions or a Linux computer.

It was tested on macOS 15 (Sequoia) with a 2 TB My Book Live and about 1 TB of data.

> **Read-only.** `debugfs` opens the drive without changing anything on it. Keep the original drive untouched until you've checked the copied files.

## What you need

- A Mac with enough free space for your data. Expect it to be close to the drive's "used" size.
- An account on the Mac with admin rights, because reading a raw disk needs `sudo`.
- Apple's command-line developer tools. If you don't have them, run `xcode-select --install`.
- A SATA-to-USB adapter or dock for the bare drive.

## Why the usual tools fail

- **macOS** doesn't read ext4 at all, so it says it "cannot read" the disk.
- **ext4fuse, and often Paragon extFS:** the My Book Live formatted its data partition with **64 KB blocks**, because it ran on a PowerPC CPU. Most Mac ext4 tools only expect 4 KB blocks, so they fail or show nothing.
- **`debugfs`** reads the file system itself in user space and handles 64 KB blocks without trouble.

## Step by step

### 1. Find the data partition

Connect the drive and run:

```bash
diskutil list external
```

A My Book Live disk looks roughly like this:

```
/dev/disk4 (external, physical):
   1:  Microsoft Basic Data   512.8 MB   disk4s3
   2:  Linux_RAID             2.0 GB     disk4s1
   3:  Linux_RAID             2.0 GB     disk4s2
   4:  Microsoft Basic Data   2.0 TB     disk4s4   <- your data
```

The **largest** partition is the data partition (here `disk4s4`). Your disk number may be different, so use yours everywhere below. In this guide it's written as `diskNsM`.

### 2. Build `debugfs`

Homebrew can install `e2fsprogs`, but building from the official source avoids problems such as Homebrew being installed under a different admin account. It takes a few minutes and needs no admin rights:

```bash
mkdir -p ~/e2fs && cd ~/e2fs && curl -fLO https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.47.1/e2fsprogs-1.47.1.tar.gz && tar xzf e2fsprogs-1.47.1.tar.gz && cd e2fsprogs-1.47.1 && ./configure --disable-nls --disable-fuse2fs && make libs && make -C debugfs
```

It worked if a line near the end says `LD debugfs`. Warnings about `dd` or "duplicate libraries" are harmless.

To keep the commands below short:

```bash
DBG=~/e2fs/e2fsprogs-1.47.1/debugfs/debugfs
```

### 3. Look around (read-only)

```bash
sudo DEBUGFS_PAGER=__none__ $DBG -R "ls -l /" /dev/diskNsM
```

You should see `shares`, `backup`, `cache` and `lost+found`. Your files are under **`/shares`**. `cache` is the device's own internal data, and `backup` is often empty.

```bash
sudo DEBUGFS_PAGER=__none__ $DBG -R "ls -l /shares" /dev/diskNsM
```

`DEBUGFS_PAGER=__none__` stops the output from opening in a pager. Without it you land on an `(END)` screen, and you have to press **q** to leave it.

To browse interactively, run `sudo $DBG /dev/diskNsM`, then use `cd`, `ls -l` and `pwd`. Type `q` to quit.

### 4. Check that it will fit

```bash
sudo DEBUGFS_PAGER=__none__ $DBG -R "stats" /dev/diskNsM | grep -iE "^block count|^free blocks|^block size"
```

The space used is (block count − free blocks) × block size, in bytes. Compare it with the free space on your Mac (`df -h ~`).

### 5. Copy everything

```bash
mkdir -p ~/MyBookLive && caffeinate -i sudo DEBUGFS_PAGER=__none__ $DBG -R "rdump /shares $HOME/MyBookLive" /dev/diskNsM 2>&1 | tee ~/MyBookLive-copy.log
```

- `caffeinate -i` stops the Mac from sleeping during a copy that can take many hours. USB 3 copies run at about 20–40 MB/s, or roughly 10 hours for 1 TB.
- `tee` saves any error messages to `~/MyBookLive-copy.log` so you can check them afterwards.
- The copy shows no progress of its own. See [Watching progress](#watching-progress).

**Skipping a big folder.** `rdump` copies a whole folder and can't leave anything out. To skip one folder (for example `Movies`), build a list of everything else and run that instead. See [Skipping folders](#skipping-folders).

### 6. Make the files yours

The copy runs as the system admin, so the copied files are owned by `root`, and Finder will ask for a password whenever you try to change them. Fix that with:

```bash
sudo chown -R $(whoami) ~/MyBookLive
```

If you ran the copy from a different admin account, put your own short username in place of `$(whoami)`.

### 7. Check for skipped folders (upper/lowercase name clashes)

Linux allows two folders whose names differ only in capital letters, such as `Photos` and `photos`. macOS treats those as the **same** name. When that happens, `rdump` prints something like

```
rdump: File exists while making directory .../photos
```

and **skips the second folder's contents**. Search your log for it:

```bash
grep "File exists" ~/MyBookLive-copy.log
```

For each folder it lists, copy the skipped one into a separate place, then compare or merge the two by hand:

```bash
mkdir -p ~/MyBookLive/extra && sudo $DBG -R 'rdump "/shares/path/to/photos" '"$HOME"'/MyBookLive/extra' /dev/diskNsM && sudo chown -R $(whoami) ~/MyBookLive/extra
```

Often the two folders turn out to be duplicates, but check them before you delete anything.

### 8. Eject

Make sure no `debugfs` is still running. A forgotten `(END)` screen keeps the disk busy and blocks ejecting. Then run:

```bash
diskutil eject diskN
```

If the eject fails, find and stop the leftover process:

```bash
ps aux | grep [d]ebugfs
```

```bash
sudo kill <PID>
```

## Watching progress

[`scripts/progress.sh`](scripts/progress.sh) shows a progress bar with GB copied, speed and an estimated time left. It also says when the copy has finished. Run it in a **second** Terminal window while the copy runs:

```bash
bash scripts/progress.sh /dev/diskNsM ~/MyBookLive/shares
```

The total it measures against is everything stored on the drive. If you skipped folders, the bar will stop short of 100%.

## Skipping folders

This builds a command list from the top-level items in `/shares`, leaves out `Movies`, and shows you the list before anything is copied:

```bash
mkdir -p ~/MyBookLive/shares && sudo DEBUGFS_PAGER=__none__ $DBG -R "ls -p /shares" /dev/diskNsM | awk -F/ 'NF>=7 && $6!="." && $6!=".." && $6!="Movies" {print "rdump \"/shares/" $6 "\" '"$HOME"'/MyBookLive/shares"}' > ~/MyBookLive/copy.txt && cat ~/MyBookLive/copy.txt
```

Then run the list. `debugfs` prints each command as it starts, which also gives you a rough idea of progress:

```bash
caffeinate -i sudo $DBG -f ~/MyBookLive/copy.txt /dev/diskNsM 2>&1 | tee ~/MyBookLive-copy.log
```

Folder names are case-sensitive here. Check that the folder you want to skip doesn't appear in the printed list.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Sorry, try again` at `Password:` | That's `sudo` asking for **your Mac login password**. Nothing shows on screen while you type. |
| `a password is required` | The password prompt got no input, for example Return was pressed too early. Run the command again. |
| `... is not in the sudoers file` | Your account isn't an admin. Run the `sudo` steps from an admin account. |
| `brew install` fails with odd errors | Homebrew may belong to another admin user. Build from source as in step 2. |
| `(END)` and the terminal seems stuck | You're in a pager. Press **q**, or add `DEBUGFS_PAGER=__none__` to the command. |
| `File exists while making directory` | Upper/lowercase name clash. See step 7. |
| `Volume failed to eject` | A `debugfs` process is still running. See step 8. |
| Chinese or other non-English names show as `\xe6\x96\xb0…` in `ls` | That's just how `debugfs` displays UTF-8 bytes. The copied files keep their proper names. |

## What we learned

See [LESSONS.md](LESSONS.md).

## License

MIT. Use at your own risk; this guide only reads the source drive, but always keep the original until you've checked the copy.
