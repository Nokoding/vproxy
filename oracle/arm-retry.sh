#!/usr/bin/env bash
# Keeps trying to create a free Ampere A1 (ARM) server until Oracle has room.
# Run it in Oracle Cloud Shell (the >_ icon in the console), not on the VM.
# Needs ~/ssh-key.key in Cloud Shell (the private key you uploaded).
# It stops by itself when the server is created. Ctrl-C stops it earlier.
#
# Creates: vproxy-arm, VM.Standard.A1.Flex, 1 OCPU, 6 GB, Ubuntu 24.04 (aarch64),
# in the first subnet it finds in your root compartment, with a public IP.
# Free allowance is 2 OCPU and 12 GB of ARM total, so this leaves half for later.

set -uo pipefail

OCPUS="${OCPUS:-1}"
MEM_GB="${MEM_GB:-6}"
NAME="${NAME:-vproxy-arm}"
KEY="${KEY:-$HOME/ssh-key.key}"
PAUSE="${PAUSE:-30}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1"; exit 1; }; }
need oci; need jq; need ssh-keygen

if [ ! -f "$KEY" ]; then
  echo "Can not find $KEY. Upload your private key to Cloud Shell and name it ssh-key.key."
  exit 1
fi
ssh-keygen -y -f "$KEY" > "$HOME/ssh-key.pub" || { echo "Could not read the key."; exit 1; }

T="${OCI_TENANCY:-}"
if [ -z "$T" ]; then
  T="$(grep -h -m1 '^tenancy=' "$HOME/.oci/config" /etc/oci/config 2>/dev/null | head -1 | cut -d= -f2)"
fi
if [ -z "$T" ]; then
  echo "Could not find your tenancy OCID. Run with it set, like:"
  echo "  OCI_TENANCY=ocid1.tenancy.oc1..xxxx bash arm-retry.sh"
  exit 1
fi

echo "Looking up the network, image and availability domains..."
SUBNET="$(oci network subnet list --compartment-id "$T" --lifecycle-state AVAILABLE \
  --query 'data[0].id' --raw-output 2>/dev/null)"
IMG="$(oci compute image list --compartment-id "$T" --operating-system 'Canonical Ubuntu' \
  --operating-system-version '24.04' --shape VM.Standard.A1.Flex \
  --sort-by TIMECREATED --sort-order DESC --query 'data[0].id' --raw-output 2>/dev/null)"
ADS="$(oci iam availability-domain list --compartment-id "$T" --query 'data[].name' 2>/dev/null | jq -r '.[]')"

if [ -z "$SUBNET" ] || [ "$SUBNET" = "null" ]; then echo "No subnet found."; exit 1; fi
if [ -z "$IMG" ] || [ "$IMG" = "null" ]; then echo "No Ubuntu 24.04 ARM image found."; exit 1; fi
if [ -z "$ADS" ]; then echo "No availability domains found."; exit 1; fi

echo "Subnet:  $SUBNET"
echo "Image:   $IMG"
echo "Domains: $(echo "$ADS" | tr '\n' ' ')"
echo "Trying every ${PAUSE}s. Leave this tab open. It stops when the server is created."
echo

n=0
while true; do
  for AD in $ADS; do
    n=$((n + 1))
    out="$(oci compute instance launch \
      --availability-domain "$AD" --compartment-id "$T" \
      --shape VM.Standard.A1.Flex \
      --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM_GB}" \
      --image-id "$IMG" --subnet-id "$SUBNET" --assign-public-ip true \
      --display-name "$NAME" --ssh-authorized-keys-file "$HOME/ssh-key.pub" 2>&1)"
    rc=$?
    if [ $rc -eq 0 ]; then
      ID="$(echo "$out" | jq -r '.data.id')"
      echo "$(date +%T)  attempt $n  $AD  CREATED"
      echo "Instance: $ID"
      echo "Waiting a minute for the public IP..."
      sleep 60
      oci compute instance list-vnics --instance-id "$ID" \
        --query 'data[0]."public-ip"' --raw-output 2>/dev/null
      echo "Log in with: ssh -i ~/ssh-key.key ubuntu@THAT_IP"
      exit 0
    fi
    if echo "$out" | grep -qiE 'out of (host )?capacity|TooManyRequests|InternalError|Out of host capacity'; then
      echo "$(date +%T)  attempt $n  $AD  no room yet"
    else
      echo "$(date +%T)  attempt $n  $AD  stopped on an error:"
      echo "$out" | head -20
      exit 1
    fi
    sleep "$PAUSE"
  done
done
