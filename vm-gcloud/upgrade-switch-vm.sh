
## Upgrades a Talkyard server in Google Cloud, by creating a machine image and a new VM
## from that image, upgrading the new VM and then moving the IP to the new VM.
##


# Get the current Talkyard VM name, network info, Talkyard branch etc:
source upgrade-switch-vm.env


# ----- Clone current VM

# Show under maintenance message.
gcloud compute  ssh  $TY_OLD_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  \
    --command='cd /opt/talkyard && sudo /usr/local/bin/docker-compose exec -T rdb psql talkyard talkyard -c "update system_settings_t set maintenance_until_unix_secs_c = 1;"'

# Create a machine image from the current VM:
gcloud compute machine-images  create $TY_NEW_IMG_NAME  --source-instance=$TY_OLD_VM_NAME  \
    --source-instance-zone=$TY_ZONE --storage-location=$TY_REGION  --project=$TY_PROJ

# Create a new VM — a copy of the current VM:
# TODO:  Use Debian 11 not 12 — currently (July 2023), 11 works better with Google Cloud:
# more secure boot.  E.g.  --no-shielded-secure-boot   can be removed? And some flags added?
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

# TODO: check exit code, here and everywhere.

echo "New VM created. If you need to, you can ssh into it:"
echo "gcloud compute  ssh $TY_NEW_VM_NAME  --project $TY_PROJ --zone $TY_ZONE"


# ----- Upgrade new VM

# Upgrade, in the new VM.
gcloud compute ssh  $TY_NEW_VM_NAME --project $TY_PROJ --zone $TY_ZONE \
    --command "set -x && cd /opt/talkyard/versions && sudo git checkout -B $TY_NEW_GIT_BRANCH origin/$TY_NEW_GIT_BRANCH && cd /opt/talkyard && sudo ./scripts/upgrade-if-needed.sh"

# Smoke test new VM.
# **** Will fail.  Smoke tests script not yet created. TODO ****
gcloud compute ssh  $TY_NEW_VM_NAME --project $TY_PROJ --zone $TY_ZONE \
    --command "cd /opt/talkyard && sudo ./scripts/run-smoke-tests.sh"

smoke_exit_code="$?"
if [ "$smoke_exit_code" -ne "0" ]; then
  echo "Error: Smoke tests failed. Aborting."
  exit $smoke_exit_code
fi

# Remove under maintenance message, from the *new* VM only.
gcloud compute  ssh  $TY_NEW_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  \
    --command='cd /opt/talkyard && sudo /usr/local/bin/docker-compose exec -T rdb psql talkyard talkyard -c "update system_settings_t set maintenance_until_unix_secs_c = null;"'


# ----- Move IP to new VM

# See:  https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address#IP_assign

# Check that the current VM NAT and IP is as expected?  TODO: Abort if any exit code $? is not 0.
gcloud compute instances describe  $TY_OLD_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  | egrep "^ *name: $TY_VM_ACCESS_CONF_NAME$"
gcloud compute instances describe  $TY_OLD_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  | egrep "^ *natIP: $TY_VM_IP$"

# First unassign the new VM's ephemeral IP:
gcloud compute instances delete-access-config  $TY_NEW_VM_NAME  --access-config-name="$TY_VM_ACCESS_CONF_NAME"  --project $TY_PROJ  --zone $TY_ZONE

# Then unassign the IP we want to use, from the old VM:
gcloud compute instances delete-access-config  $TY_OLD_VM_NAME  --access-config-name="$TY_VM_ACCESS_CONF_NAME"  --project $TY_PROJ  --zone $TY_ZONE

# Assign to the new VM:
gcloud compute instances add-access-config  $TY_NEW_VM_NAME  --access-config-name="$TY_VM_ACCESS_CONF_NAME" --address=$TY_VM_IP  --project $TY_PROJ  --zone $TY_ZONE


# ----- Stop old VM

gcloud compute instances stop  $TY_OLD_VM_NAME --project $TY_PROJ  --zone $TY_ZONE

# After a while:
# gcloud compute instances delete  $TY_OLD_VM_NAME --project $TY_PROJ  --zone $TY_ZONE


# ----- Final tests   TODO

echo "SHOULD smoke test against the real IP, not yet implemented."
echo "SHOULD create a backup, in the new VM, just to verify that that works?"


