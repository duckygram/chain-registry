#!/bin/bash
# The script is to help with getting S2S token for the particular system in the particular environment.
# It can be used if you have access to the Secrets Manager via Terraform.
#
# Execute the script without parameters to see the usage help.

usage() {
  echo "Usage:"
  echo "  $0 <ENVIRONMENT> <SYSTEM-NAME> <TENANT=devlab>"
}

environment=${1}
system=${2}
tenant=${3:-"devlab"}
[ "$environment" ] || { echo "No ENVIRONMENT parameter given"; usage; exit 1; }
[ "$system" ] || { echo "No SYSTEM-NAME parameter given"; usage; exit 1; }

s2sSecret=$(aws secretsmanager get-secret-value --secret-id "platform/environment/$environment/identity/s2s/s2s-system-$tenant-$system")
[ "$s2sSecret" ] || { echo "Secret for given system is not found"; exit 1; }

s2sSecretValue=$(echo "$s2sSecret" | jq -r '.SecretString' | sed 's/\\"/"/g')
clientId=$(echo "$s2sSecretValue" | jq -r '.client_id')
clientSecret=$(echo "$s2sSecretValue" | jq -r '.client_secret')
token=$(oauth2c -s "https://s2s.$environment.identity.our-own.cloud" \
        --client-id "$clientId" \
        --client-secret "$clientSecret" \
        --grant-type client_credentials \
        --response-types token \
        --auth-method client_secret_post \
        | jq -r '.access_token')
[ "$token" ] || { echo "Error during exchange client credentials"; exit 1; }

echo "Bearer $token"
