#!/bin/bash

## Upgrades a Talkyard server in Google Cloud, by creating a machine image and a new VM
## from that image, upgrading the new VM and then moving the IP to the new VM.
##

echo "Script not finished, some commands are still pseudo code. Bye"
exit 1

# Get the current Talkyard VM name, network info, Talkyard branch etc:
source upgrade-switch-vm.env

PROJ_ZONE="--project=$TY_PROJ --zone=$TY_ZONE"

NEW_PROD_TGT_INST="$TY_NEW_VM_NAME-prod-target"
NEW_SMOKE_TGT_INST="$TY_NEW_VM_NAME-smoke-target"
OLD_PROD_TGT_INST="$TY_OLD_VM_NAME-prod-target"
OLD_SMOKE_TGT_INST="$TY_OLD_VM_NAME-smoke-target"
OLDER_PROD_TGT_INST="$TY_OLDER_VM_NAME-prod-target"
OLDER_SMOKE_TGT_INST="$TY_OLDER_VM_NAME-smoke-target"


# ----- Prepare network

if  gcloud compute target-instances list --filter="name=('$OLDER_SMOKE_TGT_INST')"  $PROJ_ZONE
  gcloud compute target-instances delete  $OLDER_SMOKE_TGT_INST  $PROJ_ZONE
fi

if  gcloud compute target-instances list --filter="name=('$OLDER_PROD_TGT_INST')"  $PROJ_ZONE
  gcloud compute target-instances delete  $OLDER_PROD_TGT_INST  $PROJ_ZONE
fi

if  ! gcloud compute target-instances list --filter="name=('$NEW_SMOKE_TGT_INST' )"  $PROJ_ZONE
  gcloud compute target-instances create  $NEW_SMOKE_TGT_INST --instance=$TY_NEW_VM_NAME  $PROJ_ZONE
fi

if  ! gcloud compute target-instances list --filter="name=('$NEW_PROD_TGT_INST"  $PROJ_ZONE
  gcloud compute target-instances create  $NEW_PROD_TGT_INST  --instance=$TY_NEW_VM_NAME  $PROJ_ZONE
fi

if  !  gcloud compute forwarding-rules list --filter="name=( 'smoke_fwd_rule' )"  $PROJ_ZONE
  gcloud compute forwarding-rules create  smoke_fwd_rule \
    --load-balancing-scheme=EXTERNAL \
    --region=$TY_REGION \
    --ip-protocol=TCP \
    --address=$TY_VM_SMOKE_IP \
    --ports=80,443,22 \
    --target-instance=$OLD_SMOKE_TGT_INST \
    --target-instance-zone=$TY_ZONE
fi

if  !  gcloud compute forwarding-rules list --filter="name=( 'prod_fwd_rule' )"  $PROJ_ZONE
  gcloud compute forwarding-rules create  prod_fwd_rule \
    --load-balancing-scheme=EXTERNAL \
    --region=$TY_REGION \
    --ip-protocol=TCP \
    --address=$TY_VM_IP \
    --ports=80,443,22 \
    --target-instance=$OLD_PROD_TGT_INST \
    --target-instance-zone=$TY_ZONE
fi


# ----- Smoke test current VM

# So we know it works, before upgrading. Otherwise we might think the upgrade went wrong
# (rather than notiing it was broken already).

OLD_VERSION=$(curl --silent "https://$TY_PROD_HOSTNAME/-/build-info?$TY_METRICS_API_KEY" \
              | sed -nr 's/^docker tag: ([a-z0-9.-]+)$/\1/p')


# ----- Clone current VM

# TODO: curl API request instead, API secret. Next time!  This time, edit  .conf file.
# Show under maintenance message, and make Talkyard read-only.
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

# TODO: Temp disable backups
# TODO: don't prune old Docker images.
# TODO: Temp disable CDN
# TODO: Edit socket timeout: 99999
# Upgrade, in the new VM.
# TODO: Edit .env,  TODO new medium-term-stable branch  tyse-v0.2023.009
gcloud compute ssh  $TY_NEW_VM_NAME --project $TY_PROJ --zone $TY_ZONE \
    --command "set -x && cd /opt/talkyard/versions && sudo git checkout -B $TY_NEW_GIT_BRANCH origin/$TY_NEW_GIT_BRANCH && cd /opt/talkyard && sudo ./scripts/upgrade-if-needed.sh"


# Manual testing, edit IP in /etc/hosts
# All looks fine?
# TODO: Enaable CDN, restart, test a bit more
# TODO: Edit socket timeout: 60 (seconds) instead of 99999


gcloud compute forwarding-rules set-target smoke_fwd_rule --target-instance=$NEW_SMOKE_TGT_INST  $PROJ_ZONE


# Smoke test new VM.
./smoke-test.sh $TY_SMOKE_HOSTNAME $OLD_VERSION


smoke_exit_code="$?"
if [ "$smoke_exit_code" -ne "0" ]; then
  echo "Error: Smoke tests failed. Aborting."
  exit $smoke_exit_code
fi

# Remove under maintenance message, from the *new* VM only.
# TODO:  API curl request instead.
gcloud compute  ssh  $TY_NEW_VM_NAME  --project $TY_PROJ --zone $TY_ZONE  \
    --command='cd /opt/talkyard && sudo /usr/local/bin/docker-compose exec -T rdb psql talkyard talkyard -c "update system_settings_t set maintenance_until_unix_secs_c = null;"'


# ----- Point IP to new VM

gcloud compute forwarding-rules set-target prod_fwd_rule --target-instance=$NEW_PROD_TGT_INST  $PROJ_ZONE

## Could alternatively move the external IP directly, but that'd mean a tiny bit downtime (half a second or so?),
## See:  https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address#IP_assign



# ----- Stop old VM

gcloud compute instances stop  $TY_OLD_VM_NAME --project $TY_PROJ  --zone $TY_ZONE

# After a while:
# gcloud compute instances delete  $TY_OLD_VM_NAME --project $TY_PROJ  --zone $TY_ZONE


# ----- Final tests   TODO

# Smoke test new VM, the real site (not the smoke test site).
./smoke-test.sh $TY_PROD_HOSTNAME

# Verify creating backups sill works. And good to have one in any case.

gcloud compute  ssh  $TY_NEW_VM_NAME  $PROJ_ZONE  \
    --command='cd /opt/talkyard && sudo ./scripts/ ... backup ...'


# TODO: Enable backups
# TODO: Later: don't prune old Docker images.
