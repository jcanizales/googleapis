#! /bin/bash

# Example usage:
#
# ./generate_gapic_config.sh clouddebugger v2 devtools/ ~/git/googleapis ~/piper/google3
#
# Arguments:
# $1 API name (e.g. pubsub).
# $2 API version (e.g. v2).
# $3 Subdirectory of the API within googleapis/google (not including API name,
#    but including the last /, e.g. devtools/).
# $4 Absolute path to your local googleapis repo (e.g. ~/git/googleapis).
# $5 Absolute path to google3

# TODO(jcanizales): This script should live in the root of the googleapis repo.
# That would eliminate the need for the copy step (argument $2), as people can
# just work in their one local version of the repo.

set -eu -o pipefail

cd $(dirname $0)

API_NAME=$1
API_VERSION=$2
SUBDIR=$3
LOCAL_PARENT=$4
GOOGLEAPIS=$4
GOOGLE3=$5

# The pipeline tool requires the sources not to be in a GitHub repo because it
# chokes on git's metadata. So we copy protos, service config, and artman config
# to a temporary root.
TMP_ROOT=. ################################################################################

# TODO(jcanizales): Use mktemp -d instead of hard-coding the name. Also because
# we want to be sure the working directory is outside a git repo.
# mkdir artman-workspace
# cd artman-workspace/

# Copy local artman config
ARTMAN_CONFIG=gapic/api/artman_${API_NAME}.yaml
# mkdir -p ${TMP_ROOT}/gapic/api
# cp ${GOOGLEAPIS}/${ARTMAN_CONFIG} ${TMP_ROOT}/${ARTMAN_CONFIG}

# Copy public proto sources and create public service config
mkdir -p ${TMP_ROOT}/google/${SUBDIR}
cp -r ${GOOGLEAPIS}/google/${SUBDIR}${API_NAME} ${TMP_ROOT}/google/${SUBDIR}

API_DIR=google/${SUBDIR}${API_NAME}

./filter_service_yaml.py \
    ${GOOGLE3}/${API_DIR}/${API_NAME}.yaml \
    ${GOOGLE3}/${API_DIR}/prod.yaml \
    > ${API_DIR}/${API_NAME}.yaml


# Create GAPIC config

/usr/local/bin/virtualenv venv
set +u # activate uses undeclared variables
source venv/bin/activate
set -u

pip install -e git+https://github.com/googleapis/artman#egg=remote

echo "A browser window should have opened asking you to login to gcloud."
gcloud auth login
unset GOOGLE_APPLICATION_CREDENTIALS
export GCLOUD_PROJECT="vkit-pipeline"
gcloud config set project vkit-pipeline

# Temporary workaround for some mess up.
yes | pip uninstall grpc-google-logging-v2 || true
pip install 'grpc-google-logging-v2 <0.9.0,>=0.8.1'
yes | pip uninstall google-gax || true
pip install 'google-gax <0.13.0,>=0.12.5'
yes | pip uninstall grpc-google-pubsub-v1 || true
pip install 'grpc-google-pubsub-v1 <0.9.0,>=0.8.1'

# TODO(jcanizales): For some reason this doesn't show the output until the
# pipeline finishes executing. Try without pipefail?
execute_pipeline.py \
    --config "${TMP_ROOT}/${ARTMAN_CONFIG}, gapic/lang/common.yaml" \
    --env=remote \
    --local_repo=${TMP_ROOT} \
    GapicConfigPipeline \
    | tee pipeline_output

TAR_FILE=$(cat pipeline_output | tail -n1 | grep -Eo '/[0-9a-zA-Z_/-]+\.tar\.gz')

# Unzip output file
OUTPUT_FILE=google/${SUBDIR}${API_NAME}/${API_VERSION}/${API_NAME}_gapic.yaml
tar -zxvf ${TAR_FILE} googleapis/${OUTPUT_FILE}
mv googleapis/${OUTPUT_FILE} ${OUTPUT_FILE}
rm -rf googleapis

# Replace timeouts of 20s with 60s
echo "$(./correct_gapic_config_timeouts.py ${OUTPUT_FILE})" > ${OUTPUT_FILE}

# Copy it back to our local googleapis clone
# cp ${OUTPUT_FILE} ${LOCAL_PARENT}/${OUTPUT_FILE}
