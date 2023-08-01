#!/bin/bash


## Upgrades a Talkyard server in Google Cloud, by creating a machine image and a new VM
## from that image, upgrading the new VM and then moving the IP to the new VM.
##
## It's for upgrading Talkyard v2022.10 to v2023.009.

echo
echo "Read this script, and do the things therein manually, this time. Bye"
echo
exit 1


# Get the current Talkyard VM name, network info, Talkyard branch etc:
source upgrade-switch-vm.env



# ----- Prepare smoke tests
#

# Log in to the forum, as admin.  (Optionally also as an ordinary member,
# but in a different browser, e.g. Chrome + FF.)
#
# This'll give you a session cookie, so that you'll be logged in, also after the upgrade.
# Then, after the upgrade, you can post test comments, without having to log in again,
# which is helpful, if your authn system doesn't work with the new & upgraded VM, before
# the ip addr has been switched to it.
#


# ----- Show Under Maintenance message
#

# Later:
# curl -X POST --user ... $TY_REAL_HOSTNAME/-/v0/plan-maintenance -d '{ "maintenanceUntilUnixSecs": ... }'
#
# But for now:
#
# Edit /opt/talkyard/conf/play-framework.conf, add:
#
#       talkyard.maintenanceUntilUnixSeconds="1"
#
# Then:  (in /opt/talkyard/, as root)
#
#       docker-compose restart app
#
# Now a maintenance message appears, in the top nav bar (it's not customizable,
# in this old version of Ty).



# ----- Generate new VM name


# Fill in all values in ./upgrade-switch-vm.env — and let  NEW_VM_NAME  be the *current* VM name.
#
# Then run:  ./gen-next-env.sh
# (Or skip running that .sh script — instead let OLD_VM_NAME be the current name, and type
# a new name and image name yourself in the .env file.)



# ----- Clone current VM


# Create a machine image from the current VM:
gcloud compute machine-images  create $TY_NEW_IMG_NAME  --source-instance=$TY_OLD_VM_NAME  \
    --source-instance-zone=$TY_ZONE --storage-location=$TY_REGION  --project=$TY_PROJ


# Create a new VM — a copy of the current VM:
gcloud compute instances  create $TY_NEW_VM_NAME --source-machine-image=$TY_NEW_IMG_NAME \
    --project=$TY_PROJ --zone=$TY_ZONE \
    --machine-type=$TY_NEW_VM_TYPE \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=$TY_NEW_VM_SUBNET \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --instance-termination-action=STOP  \
    $TY_NEW_VM_OPT_PARAMS \
    --service-account=$TY_NEW_VM_SVC_ACCT \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --min-cpu-platform=Automatic \
    --tags=http-server,https-server \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any \
    --deletion-protection

# Check exit code

echo "New VM created. If you need to, you can ssh into it:"
echo "gcloud compute  ssh $TY_NEW_VM_NAME  --project $TY_PROJ --zone $TY_ZONE"



# ----- Prepare the upgrade


# Edit /opt/talkyard/scripts/upgrade-if-needed.sh:   (in the new VM)

#  1/2. Comment out this, for now:
#
#      log_message "Backing up before upgrading..."   <——— edit, insert "NOT Backing up"
#      ./scripts/backup.sh "$CURRENT_VERSION"         <——— comment out
#
# 2/2. Comment out this too: (the whole `if`, 3 lines — empty `if` causes an error)
#
#    if ...
#      /usr/bin/docker system prune  ...
#    fi


# Edit /opt/talkyard/conf/play-framework.conf:
#
# 1/3. Comment out:
#
#    talkyard.cdnOrigin=...
#    talkyard.cdn.origin=...
#
# 2/3. Increase the PostgreSQL timeout to 99999:
#
#    talkyard.postgresql.socketTimeoutSecs=99999
#
# 3/3. Remove the under-maintenance message, comment out: (prefix '#')
#
#    #talkyard.maintenanceUntilUnixSeconds="1"
#

# Edit /opt/talkyard/.env:
#
# 1/1  Switch to the lates medium-term-stable release branch: (tyse-v0.2023.009 as of Aug 1, 2023)
#
#   RELEASE_CHANNEL=tyse-v0.2023.009



# ----- Upgrade new VM


# Upgrade, in the new VM. (This'll use the release branch you configured just above.)
gcloud compute ssh  $TY_NEW_VM_NAME --project $TY_PROJ --zone $TY_ZONE \
    --command "set -x && cd /opt/talkyard && sudo ./scripts/upgrade-if-needed.sh"

# Smoke test new VM,

# On your laptop:

# Edit  /etc/hosts,  set   forum.yourserver.com  to point to the IP of the new & now upgraded VM.
# Open a brower, go to the forum, see if all looks fine:

# - The  Under Maintenance message should be gone
# - See if you can post some test comments (are you still logged in as admin, in your browser?).



# ----- Undo unusual settings


# 1/2. Comment back in:  (in the new VM)
#
#    talkyard.cdnOrigin=...
#    talkyard.cdn.origin=...
#
# 2/2. Change the PostgreSQL command timeout to maybe 60 seconds:
#
#    talkyard.postgresql.socketTimeoutSecs=60

# Restart:
#
#       docker-compose restart app
#
# Reloade the browser until the server is running again.



# ----- Move IP to new VM


# See:  https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address#IP_assign

# Your hosts file:
#    Comment out your /etc/hosts entry,  so you'll access the real IP again.
# Verify the maintenance message is back.

# Check that the current VM NAT and IP is as expected?  (see comment about 'name' just below)
gcloud compute instances describe  $TY_OLD_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  | egrep "^ *name: $TY_VM_ACCESS_CONF_NAME$"
gcloud compute instances describe  $TY_OLD_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  | egrep "^ *natIP: $TY_VM_IP$"

# First unassign the new VM's ephemeral IP:
# (you might need to type another access-config-name — sometimes it's "External NAT", sometimes "external-nat")
gcloud compute instances delete-access-config  $TY_NEW_VM_NAME  --access-config-name="$TY_VM_ACCESS_CONF_NAME"  --project $TY_PROJ  --zone $TY_ZONE

# Then unassign the IP we want to use, from the old VM:
gcloud compute instances delete-access-config  $TY_OLD_VM_NAME  --access-config-name="$TY_VM_ACCESS_CONF_NAME"  --project $TY_PROJ  --zone $TY_ZONE

# Assign to the new VM:
gcloud compute instances add-access-config  $TY_NEW_VM_NAME  --access-config-name="$TY_VM_ACCESS_CONF_NAME" --address=$TY_VM_IP  --project $TY_PROJ  --zone $TY_ZONE



# ----- Stop old VM

gcloud compute instances stop  $TY_OLD_VM_NAME --project $TY_PROJ  --zone $TY_ZONE

# After some weeks:
# gcloud compute instances delete  $TY_OLD_VM_NAME --project $TY_PROJ  --zone $TY_ZONE


# ----- Final smoke tests


# Post test comments.  Optionally, look in Chrome Dev Tools that you're talking to the
# correct server & IP  (which you can be pretty sure you are, if you've shut down the previous server).


# Lastly, run the backup script, on the new & now real VM:
# (and give the backups a helpful keyword name: 'afterVmImgUpgr...', will be part of the backup file names)

gcloud compute  ssh $TY_NEW_VM_NAME  --project $TY_PROJ --zone $TY_ZONE
sudo -i
cd /opt/talkyard
./scripts/backup.sh afterVmImgUpgrTo2023009


