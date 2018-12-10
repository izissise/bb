#!/bin/bash

set -euo pipefail

# Create new backup like this:
# borg init --encryption=keyfile-blake2 "$BB_DIR"
# Keyfile will be in /root/.config/borg/keys/

# Cache too big?
# https://borgbackup.readthedocs.io/en/stable/faq.html#the-borg-cache-eats-way-too-much-disk-space-what-can-i-do

# Example config
# # Backup source
# BB_PATH_TO_BACKUP="/"
# BB_EXCLUDE_FILE="/path_to_exclude_file"
#
# # Backup destination
# BB_DIR="/bb"
#
# BB_KEY_FILE="/path/to/keyfile"
# BB_PASSPHRASE_CMD='pass ...'
#
# BB_BEFORE_SCRIPT="/bin/true"
# BB_AFTER_SCRIPT=""

info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

CONF_FILE="$1"
. ${CONF_FILE}

export BB_DIR

info "Executing ${BB_BEFORE_SCRIPT}"
"${BB_BEFORE_SCRIPT}"

export BORG_KEY_FILE="${BB_KEY_FILE}"
export BORG_PASSPHRASE=$(${BB_PASSPHRASE_CMD})

# Minimum borg version 1.1.4

# some helpers and error handling:

info "Doing backup"

# https://borgbackup.readthedocs.io/en/stable/usage/create.html

nice -19 ionice -c3               \
  borg create                     \
    -v --stats --show-rc  --list  \
    --filter AME                  \
    --compression auto,zstd,13    \
    --exclude-caches              \
    --exclude "$BB_DIR"           \
    --exclude-from "$BB_EXCLUDE_FILE" \
    "$BB_DIR"::'{hostname}-{now:%Y-%m-%dT%H:%M:%S}' "$BB_PATH_TO_BACKUP"


backup_exit=$?
if [ ${backup_exit} -eq 1 ];
then
    info "Backup finished with an error/warning"
fi

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

nice -19 ionice -c3 \
  borg prune                          \
      --list                          \
      --prefix '{hostname}-'          \
      --show-rc                       \
      --keep-daily    7               \
      --keep-weekly   4               \
      --keep-monthly  6               \
      --keep-yearly   2               \
      "$BB_DIR"

prune_exit=$?
if [ ${prune_exit} -eq 1 ];
then
    info "Prune finished with an error/warning"
fi

info "Checking repository"

nice -19 ionice -c3 \
  borg check                          \
      "$BB_DIR"

check_exit=$?
if [ ${check_exit} -eq 1 ];
then
    info "Check finished with an error/warning"
    exit "$check_exit"
fi

unset BORG_PASSPHRASE
unset BORG_KEY_FILE

info "Executing ${BB_AFTER_SCRIPT}"
"${BB_AFTER_SCRIPT}"
