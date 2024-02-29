#!/bin/bash

if ! which gcloud >/dev/null 2>&1; then
    echo "missing gcloud cli"
    exit 1
fi
if ! which kubectl >/dev/null 2>&1; then
    echo "missing kubectl"
    exit 1
fi

kubeconfig="$HOME/.kube/gke_config"
if [[ -n "$1" ]]; then
    kubeconfig="$1"
fi

echo "writing kubeconfig to $kubeconfig" >/dev/stderr

kubeconfigdir="/tmp/kubeconfigs"
mkdir -p "$kubeconfigdir"

for projectid in $(gcloud projects list --format=json | jq -r '.[].projectId'); do
    if ! gcloud --project="$projectid" container clusters list >/dev/null 2>&1; then
        continue
    fi

    OLDIFS=$IFS
    IFS=$'\n'

    # find the iac-user account that is an owner on this project
    iacuser=$(gcloud projects get-iam-policy "$projectid" --format=json | jq -r '.bindings[] | select(.role == "roles/owner") | .members[] | select(. | contains("iac-user"))')
    if [[ -z "$iacuser" ]]; then
        echo "no iac-user owner found for $projectid" >/dev/stderr
        continue
    fi
    iacuser=$(echo "$iacuser" | cut -d':' -f2)

    for cluster in $(gcloud --project="$projectid" container clusters list | tail -n +2); do
        name=$(echo "$cluster" | cut -d' ' -f1)
        region=$(echo "$cluster" | cut -d' ' -f3)
        
        echo "building configs for cluster $name in project $projectid" >/dev/stderr

        # now we need the first config for our user 
        export KUBECONFIG="$kubeconfigdir/$projectid-$name-user.yml"
        gcloud --project="$projectid" container clusters get-credentials "$name" --region="$region"

        # now do that same but for the iac user
        export KUBECONFIG="$kubeconfigdir/$projectid-$name-admin.yml"
        if ! gcloud --impersonate-service-account="$iacuser" \
            --project="$projectid" container clusters get-credentials "$name" --region="$region"; then
            echo "you don't have permission to impersonate iac-user@$projectid.iam.gserviceaccount.com"
            continue
        fi

        awk -v iacuser="$iacuser" '
            /command: gke-gcloud-auth-plugin/ {
                print $0
                print "      args:"
                print "        - --impersonate_service_account"
                print "        - " iacuser ""
                next
            }
            { print }
            ' "$KUBECONFIG" > tmp; mv tmp "$KUBECONFIG"
    done
    IFS=$OLDIFS
done

set -e

exportstring=""
for f in "$kubeconfigdir"/*; do
    if [[ "$f" == *yml ]]; then
        exportstring="$f:$exportstring"
    fi
done

exportstring=$(echo "$exportstring" | rev | cut -c 2- | rev)
export KUBECONFIG="$exportstring"

kubectl config view --flatten > "$kubeconfig"

rm -rf "$kubeconfigdir"

cat >/dev/stderr <<EOF


generated $kubeconfig, do with it as you will
you probably want to add this to your shell though:

export KUBECONFIG="\$KUBECONFIG:$kubeconfig"
EOF
