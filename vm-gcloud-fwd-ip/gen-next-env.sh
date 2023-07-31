#!/bin/bash

## Generates names for a machine image and new VM, where we'll upgrade Talkyard.
##

## Read the current VM name etc.
source upgrade-switch-vm.env

## The old VM name becomes older. The current becomes old.
## (We'll delete a forwarding rule target instance, for the older VM, that's why we remember its name.)
TY_OLDER_VM_NAME="$TY_OLD_VM_NAME"
TY_OLD_VM_NAME="$TY_NEW_VM_NAME"

## Generate a name for the next new VM.
DATE_TIME="$(date --utc '+%y%m%d-%H%M%S')" # e.g. "230730-235959".
TY_NEW_VM_NAME="talkyard-$DATE_TIME"

## Do the actual changes (in the .env file).
sed --in-place=.prev -r  \
  -e 's:TY_OLDER_VM_NAME="[^"]*":TY_OLDER_VM_NAME="'$TY_OLDER_VM_NAME'":'  \
  -e 's:TY_OLD_VM_NAME="[^"]*":TY_OLD_VM_NAME="'$TY_OLD_VM_NAME'":'  \
  -e 's:TY_NEW_VM_NAME="[^"]*":TY_NEW_VM_NAME="'$TY_NEW_VM_NAME'":'  \
  -e 's:TY_NEW_IMG_NAME="[^"]*":TY_NEW_IMG_NAME="'$TY_OLD_VM_NAME'-mimg-'$DATE_TIME'":'  \
  upgrade-switch-vm.env


