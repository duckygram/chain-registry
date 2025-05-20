#!/bin/bash
# The script is to help with coping of values of the secrets between different environments
# It is to be used after terraform part of the target environment has already been successfully
# applied.
#
# Execute the script without parameters to see the usage help.

PROJECT_CODE=platform

usage() {
  echo "Usage:"
  echo "  $0 --from=<SOURCE-ENV> --to=<TARGET-ENV> --system=<SYSTEM-NAME>"
}

# find and return KMS key to encrypt secrets assuming it must have an alias following
# the naming scheme platform-${TO_ENV}-secrets
get_kms_key_id() {
  kms_key_alias="${PROJECT_CODE}-${TO_ENV}-secrets"
  aws kms list-aliases --output text --query "Aliases[?AliasName=='alias/$kms_key_alias'].{ID:TargetKeyId}"
  kms_key_id="$(aws kms list-aliases --output text --query "Aliases[?AliasName=='alias/$kms_key_alias'].{ID:TargetKeyId}")"
  if [ -z "$kms_key_id" ]; then
    echo "Unable to find KMS key with alias '$kms_key_alias'"
    echo "Probably you have to apply SKELETON system before attempting to copy secrets to the environment"
    exit 1
  fi
}

get_approve() {
  if [ "$AUTO_APPROVE" ]; then
    return 0
  fi

  read -p "$1 (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    return 0
  fi

  return 1
}

# decode cmdline args
AUTO_APPROVE=
for arg in "$@"
do
  case $arg in
    --from=*) \
        FROM_ENV="${arg#*=}"
        shift
        ;;
    --to=*)
        TO_ENV="${arg#*=}"
        shift
        ;;
    --system=*)
        SYSTEM="${arg#*=}"
        shift
        ;;
    --yes)
        AUTO_APPROVE=1
        shift
        ;;
    *)
        OTHER_ARGUMENTS+=("$1")
        shift # Remove generic argument from processing
        ;;
    esac
done

# check required parameters provided
[ "$FROM_ENV" ] || { echo "No --from parameter given"; usage; exit 1; }
[ "$TO_ENV" ] || { echo "No --to parameter given"; usage; exit 1; }
[ "$SYSTEM" ] || { echo "No --system parameter given"; usage; exit 1; }

# for every secret which is not marked with tag origination='generated'
for source_secret in $(aws secretsmanager list-secrets \
                           --filter Key=name,Values=$PROJECT_CODE/environment/$FROM_ENV/$SYSTEM \
                           --query "SecretList[?!(Tags[?Key=='origination' && Value=='generated'])]" \
                        | jq -r '.[].Name')
do
  secret_name_suffix=${source_secret#$PROJECT_CODE/environment/$FROM_ENV/$SYSTEM}
  target_secret="$PROJECT_CODE/environment/$TO_ENV/$SYSTEM$secret_name_suffix"
  sec_val="$(aws secretsmanager get-secret-value --secret-id="$source_secret" | jq -r '.SecretString')" \
    || echo "Unable to get secret value from '$source_secret'"

  if aws secretsmanager describe-secret --secret-id="$target_secret" >/dev/null 2>&1; then

    # target secret already exists
    if get_approve "Override secret $target_secret?"; then
      aws secretsmanager put-secret-value --secret-id="$target_secret" --secret-string="$sec_val" && \
      echo "Secret '$target_secret' updated."
    else
      echo "Secret '$target_secret' skipped."
    fi

  else

    # not target secret exists, create it
    if [ -z "$kms_key_id" ]; then
      get_kms_key_id
    fi
    if get_approve "Create secret $target_secret?"; then
      aws secretsmanager create-secret --kms-key-id "$kms_key_id" --name="$target_secret" \
        --secret-string="$sec_val" \
        --tags Key=origination,Value=manual && \
      echo "Secret '$target_secret' created."
    else
      echo "Secret '$target_secret' skipped."
    fi

  fi

done