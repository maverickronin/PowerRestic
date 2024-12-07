# PowerRestic

PowerRestic aims to be a complete text menu interface for using the restic executable on Windows, with ***local*** repositories.  PowerRestic targets PowerShell 5.1 as that's still what Windows includes by default

Creation and scheduling of backup jobs is a planned feature but its current functionality is focused on managing and restoring from existing repositories and snapshots.

## Getting Started

Just run `PowerRestic.ps1` and it will prompt you for a path to the restic executable and start up with default the settings.  It will create an .ini file which you can later edit as needed.  Jump right to the "Work with repositories" option as backup tasks are not yet implemented.

There are a few other things to keep in mind too

- Menu navigation inputs have been designed for the number pad.
- Menu navigation commands are all displayed onscreen, so specifics will not be mentioned here.
- You don't need to quote anything, even paths with spaces.
- PowerRestic automatically converts restic's internal *nix path conventions back to DOS/Windows conventions for display and does the reverse with any user input so it can be treated as a fully "native" Windows application.

## Opening Repositories

PowerRestic lets you pin a list of repositories for frequent use, open a repository by path, or create a new repository.

##### Open a pinned repository

Displays a list of repositories you have previously pinned.

##### Pin a repository

Enter the path to a repository you would like to pin.  You may opt to test it by checking if restic can read its basic configuration with `cat config`

##### Unpin a repository

Remove a repository from the pinned list.

##### Enter a repository path manually

Enter the path to a repository you would like to open.

##### Create a repository

Prompts for a path to create the repository in and a password if desired.  Asks if you would like to pin the repository after creation.

##### Opening repositories in general

PowerRestic will first attempt to "open" a repository with the `cat config` command.  It will  first attempt with the `--insecure-no-password` flag and then prompt for a password if that fails.  The password will be passed to restic via the `RESTIC_PASSWORD` environment variable.

## Working with Repositories

##### Get repository stats

Generates and displays various repository stats from the different modes of the `stats` command.

##### Check repository integrity

Provides options to check the metadata and data of the repository with the `check` command including `--read-data` and `--read-data-subset` with options to provide a percentage or fixed amount of data to read.

##### Work with snapshots

Display a list of snapshots in the repository.  Select a snapshot to restore from it or perform other operations.

##### Pin or Unpin

Pin or unpin this repository according to its current status.

##### Prune old data

Removes unreferenced data in repository with the `prune` command.  Exact settings may be specified in the .ini file.

## Working with Snapshots

Selecting a snapshot will display its basic stats and provide these other options.

##### Browse/restore from this snapshot

Opens the snapshot's directory structure at its top level and allows you to browse and restore its contents.

##### Jump to path in this snapshot

Type a path contained within the snapshot to begin browsing there instead of at the top level.

##### Forget this snapshot

Remove this individual snapshot's metadata from the repository with the `forget` command.

##### Edit this snapshot's tags

Edit the snapshot's tags with options to add or remove individual tags and to clear all tags.

## Restoring Data

PowerRestic allows you to browse the directory structure of a snapshot in order to select files or folders to restore.

Selecting a file will display its basic stats and menu options to restore it.  For a directory you must first navigate into it and then select the option to display "information about current directory".

Going forward, each user selected file or folder will be referred to as an "item".

##### Common options

- Location to restore to
    - Original location
    - Browse local file system
    - Enter path manually

- Overwrite and delete
    - All 6 combinations of `--overwrite always` (restic default, and is actually just anything changed), `--overwrite if-newer`, and `--overwrite never` crossed with `--delete` (delete files in destination that are not in the snapshot, off by default).

- Dry run
    - Perform a dry run first and choose to continue with the restore operation or not
    - By default, a log of the dry run will be opened in the default text editor

- Conformation
    - Displays a summary of the selected options.

##### Quick Restore

Skip the options menus and restore the item to the original location with the default settings of overwriting changed files, leaving extra files, and not performing a dry run first.  By default the conformation menu is still displayed but can be disabled.

##### Restore now

Proceed though the restore option menus and restore this single item.

##### Queue for restore

Add this item to a list which can be restored all at once later.  The menu for restoring queued items also lets you remove individual items or clear the queue entirely.

Queued items must all be restored to their individual original locations or to a single common location.

With a queue, dry runs can be performed in two different modes.  Each item's dry run may be done individually, in order, with a choice to for each item's restore operation or all dry runs may be done at once with a single choice to continue with all the queued restores or abort.

## Settings in the .ini File

As long as you point it to the restic executable when prompted, the script will make a basic ini file and run with defaults but you can change them here.

It's just the usual `SETTING=VALUE` and order doesn't matter.  You don't need quotes here either.

- ResticPath
    - The only thing it actually needs to run
- DisplayLines
    - Default: 40
    - Number of options in a menu before it paginates
- Retries
    - Default: 3
    - Number of failures before an otherwise un-exitable input prompt goes back to its parent menu
- AutoOpenDryRunLog
    - Default: 1
    - If dry run log files should automatically open in the default text editor after they finish - 0 or 1
- QuickRestoreConfirm
    - Default: 1
    - Display a yes/no conformation before performing a quick restore - 0 or 1
- LogPath
    - Default: \<repository path\>\pr_data
    - Path restore and dry run logs are saved to.  Can be changed to another absolute or relative path.
- Pin
    - Default: null
    - Path to any repository you'd like to pin for quick access.  Repeat on multiple lines as many times as you need.

##### Repository Prune Settings

These options will be passed to restic's prune command as set.  [Restic documentation here](https://restic.readthedocs.io/en/stable/060_forget.html) and from `restic help prune`

- PruneMaxRepackSize
    - `--max-repack-size`
    - Default: null
- PruneMaxUnused
    - `--max-unused`
    - Default: 5%
- PruneRepackCacheableOnly
    - `--repack-cacheable-only`
    - Default: 0
    - 0 or 1
- PruneRepackSmall
    - `--repack-small`
    - Default: 1
    - 0 or 1
- PruneRepackUncompressed
    - `--repack-uncompressed`
    - Default: 1
    - 0 or 1