#!/bin/bash

##
# Prerequisites:
# 0. Have this script in KRONOS repo root folder. Work from there till the end.
# 1. Have 'symphony-aws-dev-mt' aws profile setup (need user in dev-mt with api key).This is used to work with KRONOS images.
# 2. Export AWS_SECRET_ACCESS_KEY/AWS_ACCESS_KEY_ID  for env you are going to create/delete tenant in
# 3. Export ARTIFACTORY_USERNAME (your email) and ARTIFACTORY_PASSWORD (your api key in artifactory) variables
# 4. Create createTenant.properties with tenant parameters (similar to manifest for spinnaker)
# 5. Run ./make[destroy]Tenant <tenantId> <platform> <env>
##

TENANT_ID=$1
PLATFORM=$2
PMT_ENV=$3

BUILDER_IMAGE=mt-builder:$TENANT_ID
DOCKER_REPO="115671292914.dkr.ecr.us-east-1.amazonaws.com"
REGION=us-east-1
TENANT_PROPERTIES=createTenant.properties
usage="usage: makeTenant.sh <tenantId> <platform> <env>"

echo TENANT_ID=$TENANT_ID
echo PLATFORM=$PLATFORM
echo

if [ -z $TENANT_ID ]; then
  echo "ERROR: missing tenant (number);"
  echo $usage exit 1
fi
if [ -z $PLATFORM ]; then
  echo "ERROR: missing platform;"
  echo $usage exit 1
fi
if [ -z $PMT_ENV ]; then
  echo "ERROR: missing env (qa/dev etc);"
  echo $usage exit 1
fi
if [ ! -f "$TENANT_PROPERTIES" ]; then
  echo "You should define tenant's properties in $TENANT_PROPERTIES"
  echo $usage exit 1
fi

if [ -z $AWS_ACCESS_KEY_ID ]; then
  echo "Please set AWS_ACCESS_KEY_ID env var" && exit 1
fi

if [ -z $AWS_SECRET_ACCESS_KEY ]; then
  echo "Please set AWS_SECRET_ACCESS_KEY env var" && exit 1
fi

if [ -z $ARTIFACTORY_USERNAME ]; then
  echo "Please set ARTIFACTORY_USERNAME env var" && exit 1
fi

if [ -z $ARTIFACTORY_PASSWORD ]; then
  echo "Please set ARTIFACTORY_PASSWORD env var" && exit 1
fi

function readTenantArgs() {
  CREATE_TENANT_ARGS=""
  source createTenant.properties
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS}--agent $AGENT_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --api-gateway $API_GATEWAY_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --bff $BFF_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --bff-mt-enabled $BFF_MT_ENABLED"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --bff-st-enabled $BFF_ST_ENABLED"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --bootstrap $SBE_BOOTSTRAP_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --ceb $CEB_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --export $EXPORT_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --import $IMPORT_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --import-cleanup $IMPORT_CLEANUP_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --import $REINDEX_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --owner $OWNER"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --regression $REGRESSION_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --rtc-cs $RTC_CS_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --rtc-mbr-ami $RTC_MBR_AMI"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --df2-enabled $DF2_ENABLED"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --rtc-mt-enabled $RTC_MT_ENABLED"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --rtc-st-enabled $RTC_ST_ENABLED"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --sbe $SBE_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --smoke-test-platform $SMOKE_TEST_PLATFORM_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --smoke-test-tenant $SMOKE_TEST_TENANT_TAG"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --valid-email-domains $VALID_EMAIL_DOMAINS"
  CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS} --xpod-client $XPOD_CLIENT_TAG"
}

readTenantArgs
echo "About to build the tenant with such params: "
echo $CREATE_TENANT_ARGS
echo

read -p "Creating Tenant ${TENANT_ID}? (y/n)" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

echo "Logging into dev-mt docker repo"
aws ecr get-login-password --region us-east-1 --profile symphony-aws-dev-mt | docker login --username AWS --password-stdin $DOCKER_REPO
echo "Logging into docker repo: success"

echo Create tenant args: $CREATE_TENANT_ARGS

docker build \
  -f jenkins/mt-builder/Dockerfile \
  --build-arg CREATE_TENANT_SCRIPT=bin/create-tenant.sh \
  --build-arg TENANT_ID=$TENANT_ID \
  --build-arg PLATFORM=$PLATFORM \
  --build-arg ENVIRONMENT=$PMT_ENV \
  --build-arg REGION=$REGION \
  --build-arg CREATE_TENANT_ARGS="${CREATE_TENANT_ARGS}" \
  -t $BUILDER_IMAGE \
  .

mkdir -p environments/aws/$PMT_ENV/$REGION/$PLATFORM/tenants/
TENANT_YAML=environments/aws/$PMT_ENV/$REGION/$PLATFORM/tenants/$TENANT_ID.yaml
docker run --rm --entrypoint cat $BUILDER_IMAGE $TENANT_YAML >$TENANT_YAML
echo Generated $TENANT_YAML

cat $TENANT_YAML

docker run --rm \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e ARTIFACTORY_USERNAME=$ARTIFACTORY_USERNAME \
  -e ARTIFACTORY_PASSWORD=$ARTIFACTORY_PASSWORD \
  $BUILDER_IMAGE apply

echo "Done. Check tenant health with this URL:"
echo "curl https://${TENANT_ID}.${PMT_ENV}mt.symphony.com/webcontroller/HealthCheck/aggregated"
