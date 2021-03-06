#!/usr/bin/env bash

########################################################################################################################
#       Author  : Suresh Kumar                                                                                         #
#       Email   : gsuresh26kr@gmail.com                                                                               #
#       About   : This script can be used to run codebuild locally                                                     #
#       Use     : Execute this script with --help argument to know how to use this script                              #
########################################################################################################################

# Exit when any command fails
set -e
#set -x

########################################################################################################################
#   Constants                                                                                                          #
########################################################################################################################

DEFAULT_AWS_CREDENTIAL_FILE="${HOME}/.aws/credentials"
DEFAULT_BUILD_IMAGE="amazonlinux"
BUILD_MOUNT_DIR="/tmp/local-codebuild/$(date +'%d%B%Y-%HH%MM%SS')"

# Exporting color codes, so that it can be used in
export _NORMAL_CLR=$(echo -en '\033[00;0m')
export _BOLD_TEXT=$(echo -en '\033[00;1m')
export _SUCCESS_CLR=$(echo -en '\033[00;32m')
export _GENERAL_CLR=$(echo -en '\033[00;33m')
export _SUB_GEN_CLR=$(echo -en '\033[00;36m')
export _NOTE_CLR=$(echo -en '\033[00;35m')
export _ERROR_CLR=$(echo -en '\033[00;31m')

########################################################################################################################
#   Dynamic parameters for the script                                                                                  #
########################################################################################################################

# If --help argument is passed or no argument is passed
if { (($# == 1)); } && { [ $1 = "--help" ] || [ $1 == "--debug" ]; }; then

    if [ $1 == "--debug" ]; then
        set -x
    else
        cat <<HELP_DOC

    $_BOLD_TEXT LOCAL CODEBUILD $_NORMAL_CLR
HELP_DOC

        (
            echo "cat <<EOF"
            cat help.txt
            echo EOF
        ) | sh
        exit 0
    fi

else
    # If even number of arguments are not passed
    if (($# % 2 != 0)); then
        echo -e "$_ERROR_CLR> Please provide a valid argument. $_NORMAL_CLR"
        exit 1
    fi
fi

# Set parameters
function set_argument() {
    case $1 in
    --config)
        CONFIG_FILE="$2"
        ;;
    --show-build-logs)
        SHOW_BUILD_LOGS="$2"
        ;;
    *)
        echo -e "$_ERROR_CLR> Please provide a valid argument. $_NORMAL_CLR"
        exit 1
        ;;
    esac
}

# Reading ARGUMENTS
while (($# >= 2)); do
    set_argument "$1" "$2"
    shift 2
done

########################################################################################################################
# READING CONFIGURATION                                                                                                #
########################################################################################################################

function read_configuration() {
    # If config file parameter is not set
    if [ -v ${CONFIG_FILE} ]; then
        echo -e "$_GENERAL_CLR> Configuration file is not provided, so reading default file - ${_SUB_GEN_CLR} local_codebuild_config.yml${_GENERAL_CLR}. $_NORMAL_CLR"
        CONFIG_FILE="local_codebuild_config.yml"
    fi

    # Checking if config file exists
    if [ -f ${CONFIG_FILE} ]; then
        echo -e "$_GENERAL_CLR> Fetching configuration from file - ${_SUB_GEN_CLR} ${CONFIG_FILE}${_GENERAL_CLR}. $_NORMAL_CLR"

        # Setting Parameters
        DEPLOYMENT_SOURCE_TYPE=$(cat $CONFIG_FILE | wildq --input yaml ".deployment_source_type")
        DEPLOYMENT_SOURCE=$(cat $CONFIG_FILE | wildq --input yaml ".deployment_source")
        AWS_PROFILE=$(cat $CONFIG_FILE | wildq --input yaml ".aws_profile")
        BUILDSPEC_FILE=$(cat $CONFIG_FILE | wildq --input yaml ".buildspec_file")
        TEMP_AWS_CREDENTIAL_FILE=$(cat $CONFIG_FILE | wildq --input yaml ".aws_credential_file")
        TEMP_BUILD_IMAGE=$(cat $CONFIG_FILE | wildq --input yaml ".build_image")
        # NOTE - wildq returns None if key is not found

    else
        echo -e "$_ERROR_CLR> Configuration file ${_SUB_GEN_CLR}${CONFIG_FILE}${_ERROR_CLR} does not exists. Please provide a valid configuration file. $_NORMAL_CLR"
        exit 1
    fi

}

########################################################################################################################
# VALIDATE AND SET CONFIGURATION PARAMETERS                                                                                          #
########################################################################################################################

# Function to read credentials from credential file
function fetch_credentials() {

    # Setting Profile
    AWS_PROFILE_ARG=$1

    # Setting Credential File
    AWS_CREDENTIAL_FILE=$2

    # Checking if credential file exists
    if [ -f ${AWS_CREDENTIAL_FILE} ]; then
        echo -e "$_GENERAL_CLR> Fetching AWS credentials from credentials file - $_SUB_GEN_CLR ${AWS_CREDENTIAL_FILE} ${_GENERAL_CLR}- for profile ${_SUB_GEN_CLR}${AWS_PROFILE_ARG}${_GENERAL_CLR}.${_NORMAL_CLR}"
    else
        echo -e "$_ERROR_CLR> AWS credential file ${_SUB_GEN_CLR}${AWS_CREDENTIAL_FILE}${_ERROR_CLR} does not exists. Please provide a valid credential file. $_NORMAL_CLR"
        exit 1
    fi

    # Reading credentials from provided profile
    credentials=$(cat ${AWS_CREDENTIAL_FILE} | wildq --input ini "." --output json --monochrome-output | jq ".${AWS_PROFILE_ARG}")

    # If profile exists in the credentials file
    if [ "${credentials}" != "null" ]; then

        # This export is not necessary, if variable is set even without export, it will be accessible while running script
        export AWS_ACCESS_KEY_ID=$(echo $credentials | jq -r .aws_access_key_id)
        export AWS_SECRET_ACCESS_KEY=$(echo $credentials | jq -r .aws_secret_access_key)
        export AWS_SESSION_TOKEN=$(echo $credentials | jq -r .aws_session_token)
        export AWS_DEFAULT_REGION=$(echo $credentials | jq -r .region)
    else
        echo "${_ERROR_CLR}> ${_SUB_GEN_CLR}${AWS_PROFILE_ARG}${_ERROR_CLR} profile does not exists in credential file - $_SUB_GEN_CLR $AWS_CREDENTIAL_FILE. $_NORMAL_CLR"
        exit 1
    fi
}

function validate_and_set_aws_credentials() {
    # Setting AWS Credentials file if provided in configurations or else using default value
    if [ "$TEMP_AWS_CREDENTIAL_FILE" != "None" ]; then

        # Setting credential file
        AWS_CREDENTIAL_FILE=$TEMP_AWS_CREDENTIAL_FILE

    else
        AWS_CREDENTIAL_FILE=$DEFAULT_AWS_CREDENTIAL_FILE
    fi

    # AWS PROFILE
    if [ $AWS_PROFILE != "None" ]; then

        # Reading Credentials
        if [ $AWS_PROFILE == "default" ]; then
            if [ -v ${AWS_ACCESS_KEY_ID} ] && [ -v ${AWS_SECRET_ACCESS_KEY} ]; then

                # Fetching credentials
                fetch_credentials $AWS_PROFILE $AWS_CREDENTIAL_FILE

            else

                echo -e "$_GENERAL_CLR> Fetching credentials from environment variables. $_NORMAL_CLR"
            fi
        fi
    else
        echo -e "$_ERROR_CLR> Please provide a valid deployment source type. $_NORMAL_CLR"
        exit 1
    fi

}

function validate_and_set_deployment_source() {
    # DEPLOYMENT SOURCE
    if [ "$DEPLOYMENT_SOURCE_TYPE" != "None" ]; then
        # If DEPLOYMENT_SOURCE_TYPE is neither git nor local
        if ! { [ "$DEPLOYMENT_SOURCE_TYPE" == "git" ] || [ "$DEPLOYMENT_SOURCE_TYPE" == "local" ]; }; then
            echo -e "$_ERROR_CLR> Please provide a valid deployment source type. Check parameter ${_SUB_GEN_CLR}deployment_source_type${_ERROR_CLR} in your configuration file.$_NORMAL_CLR"
            exit 1
        else
            echo -e "$_GENERAL_CLR> Setting deployment source type as - ${_SUB_GEN_CLR} ${DEPLOYMENT_SOURCE_TYPE}${_GENERAL_CLR}.${_NORMAL_CLR}"

            # DEPLOYMENT SOURCE
            if [ "$DEPLOYMENT_SOURCE" != "None" ]; then
                if [ "$DEPLOYMENT_SOURCE_TYPE" == "git" ]; then
                    echo -e "$_GENERAL_CLR> Setting deployment source as ${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE}${_GENERAL_CLR}. Make sure this is valid. You are responsible for what happens next.${_NORMAL_CLR}"
                else
                    if [ "$DEPLOYMENT_SOURCE_TYPE" == "local" ]; then

                        # Checking if source directory exists
                        if [ -d $DEPLOYMENT_SOURCE ]; then
                            echo -e "$_GENERAL_CLR> Setting deployment source as '${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE}${_GENERAL_CLR}'. Make sure this is valid. You are responsible for what happens next.${_NORMAL_CLR}"
                        else
                            echo -e "$_ERROR_CLR> Please provide a valid deployment source. Check parameter ${_SUB_GEN_CLR}deployment_source${_ERROR_CLR} in your configuration file. $_NORMAL_CLR"
                            exit 1
                        fi
                    fi
                fi
            else
                echo -e "$_ERROR_CLR> Please provide a valid deployment source. Check parameter ${_SUB_GEN_CLR}deployment_source${_ERROR_CLR} in your configuration file. $_NORMAL_CLR"
                exit 1
            fi
        fi
    else
        echo -e "$_ERROR_CLR> Please provide a valid deployment source type. Check parameter ${_SUB_GEN_CLR}deployment_source_type${_ERROR_CLR} in your configuration.$_NORMAL_CLR"
        exit 1
    fi

}

# Validate BuildSpec file
function validate_buildspec() {

    if [ "$BUILDSPEC_FILE" != "None" ]; then

        if [ "$DEPLOYMENT_SOURCE_TYPE" == "git" ]; then
            echo -e "$_NOTE_CLR> Since deployment source is set to ${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE_TYPE}${_NOTE_CLR}, not validating BuildSpec file.${_NORMAL_CLR}"
        else
            if [ "$DEPLOYMENT_SOURCE_TYPE" == "local" ]; then
                if [ -f "${DEPLOYMENT_SOURCE}/${BUILDSPEC_FILE}" ]; then
                    echo -e "$_GENERAL_CLR> Setting BuildSpec file path to  '${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE}/${BUILDSPEC_FILE}${_GENERAL_CLR}'. Make sure this is valid BuildSpec file. $_NORMAL_CLR"
                else
                    echo -e "$_ERROR_CLR> Please provide a valid BuildSpec file. Check parameter ${_SUB_GEN_CLR}buildspec_file${_ERROR_CLR} in your configuration. ${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE}/${BUILDSPEC_FILE}${_ERROR_CLR} file does not exist.$_NORMAL_CLR"
                    exit 1
                fi
            fi
        fi
    else
        echo -e "$_ERROR_CLR> Please provide a valid BuildSpec file.$_NORMAL_CLR"
        exit 1
    fi

}

# Set Build Image
function set_build_image() {
    if [ "$TEMP_BUILD_IMAGE" != "None" ]; then

        # Setting build image
        BUILD_IMAGE=$TEMP_BUILD_IMAGE

        echo -e "$_GENERAL_CLR> Setting Build Image - ${_SUB_GEN_CLR}${BUILD_IMAGE}${_GENERAL_CLR}. $_NORMAL_CLR"

    else
        # Setting default build image
        BUILD_IMAGE=$DEFAULT_BUILD_IMAGE

        echo -e "$_NOTE_CLR> Build Image is not provided in configuration file. Using default build image - ${_SUB_GEN_CLR}${BUILD_IMAGE}${_NOTE_CLR}. $_NORMAL_CLR"
    fi
}

# Validates and Sets configuration parameters defined in configuration file
function set_configuration_parameters() {

    # Set AWS Credentials
    validate_and_set_aws_credentials

    # Set Deployment Source
    validate_and_set_deployment_source

    # Validate Buildspec
    validate_buildspec

    # Set Build Image
    set_build_image
}

########################################################################################################################
# BUILD DIR AND ENTRYPOINT SCRIPT                                                                                      #
########################################################################################################################

function create_build_mount_dir() {

    echo -e "$_GENERAL_CLR> Setting Build Mount Directory - ${_SUB_GEN_CLR}${BUILD_MOUNT_DIR}${_GENERAL_CLR}. $_NORMAL_CLR"
    mkdir -p ${BUILD_MOUNT_DIR}

    echo -e "$_GENERAL_CLR> Copying build code to - ${_SUB_GEN_CLR}${BUILD_MOUNT_DIR}${_GENERAL_CLR}. $_NORMAL_CLR"

    # If local -> Copy local code
    if [ ${DEPLOYMENT_SOURCE_TYPE} == "local" ]; then
        echo -e "$_GENERAL_CLR> Copying locally from - ${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE}${_GENERAL_CLR}. $_NORMAL_CLR"
        cp -pr ${DEPLOYMENT_SOURCE} ${BUILD_MOUNT_DIR}/code

    else
        if [ ${DEPLOYMENT_SOURCE_TYPE} == "git" ]; then
            echo -e "$_GENERAL_CLR> Copying from git - ${_SUB_GEN_CLR}${DEPLOYMENT_SOURCE}${_GENERAL_CLR}. $_NORMAL_CLR"
        fi
    fi

    # Else if git -> Copy from git

}

function create_entrypoint_script() {

    # Check BuildSpec file.
    if [ -f "${BUILD_MOUNT_DIR}/code/${BUILDSPEC_FILE}" ]; then
        echo -e "$_GENERAL_CLR> Reading BuildSpec file - '${_SUB_GEN_CLR}${BUILD_MOUNT_DIR}/code/${BUILDSPEC_FILE}${_GENERAL_CLR}'.$_NORMAL_CLR"

        # Entrypoint Script
        ENTRYPOINT_SCRIPT=${BUILD_MOUNT_DIR}/code/local-codebuild-main.sh

        # Creating a bash script which will be used for entrypoint
        echo -e "$_GENERAL_CLR> Created ENTRYPOINT script - '${_SUB_GEN_CLR}${ENTRYPOINT_SCRIPT}${_GENERAL_CLR}'.$_NORMAL_CLR"
        echo -e "#!/usr/bin/env bash\n" >${ENTRYPOINT_SCRIPT}
        echo -e "set -x" >>${ENTRYPOINT_SCRIPT}

        echo -e "\n# Switching to appropriate work directory" >>${ENTRYPOINT_SCRIPT}
        echo -e "cd /code" >>${ENTRYPOINT_SCRIPT}

        # READING BUILD SPEC FILE AND UPDATING THE BASH SCRIPT WHICH WILL BE USED FOR ENTRYPOINT
        # Read Install Command
        echo -e "\n# INSTALL" >>${ENTRYPOINT_SCRIPT}
        cat ${BUILD_MOUNT_DIR}/code/${BUILDSPEC_FILE} |
            wildq --input yaml ".phases.install.commands" --output json --monochrome-output |
            jq -c -r '.[]' >>${ENTRYPOINT_SCRIPT}

        echo -e "# BUILD" >>${ENTRYPOINT_SCRIPT}
        cat ${BUILD_MOUNT_DIR}/code/${BUILDSPEC_FILE} |
            wildq --input yaml ".phases.build.commands" --output json --monochrome-output |
            jq -c -r '.[]' >>${ENTRYPOINT_SCRIPT}

        # Making entrypoint script executable
        chmod +x ${ENTRYPOINT_SCRIPT}

    else
        echo -e "$_ERROR_CLR> Error reading BuildSpec file - '${_SUB_GEN_CLR}${BUILD_MOUNT_DIR}/code/${BUILDSPEC_FILE}${_GENERAL_CLR}'.$_NORMAL_CLR"
        exit 1
    fi

}

########################################################################################################################
# RUN BUILD                                                                                                            #
########################################################################################################################


function run_build() {

    # Run container
    container_id=$(
        docker run \
            -d \
            --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
            --env AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
            --env AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN} \
            --env AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
            --volume \
            ${BUILD_MOUNT_DIR}/code:/code \
            ${BUILD_IMAGE} \
            bash code/local-codebuild-main.sh
    )

    # If execution is successful
    if [ "$?" -eq 0 ]; then
        echo -e "$_GENERAL_CLR> Executed container - '${_SUB_GEN_CLR}${container_id}${_GENERAL_CLR}'.$_NORMAL_CLR"
        if [ "$SHOW_BUILD_LOGS" == "yes" ]; then
            echo -e "${_NOTE_CLR}\n===============================================================$_NORMAL_CLR"
            echo -e "${_NOTE_CLR}=         BUILD LOGS - CONTAINER                              =$_NORMAL_CLR"
            echo -e "${_NOTE_CLR}===============================================================$_NORMAL_CLR"

            # Show Logs
            docker logs -f ${container_id}
        else
            echo -e "$_GENERAL_CLR> Run following command to check logs $_NORMAL_CLR"
            echo -e "${_SUB_GEN_CLR}   docker logs -f ${container_id} $_NORMAL_CLR"
        fi
    else
        echo -e "$_ERROR_CLR> Error while running docker container.$_NORMAL_CLR"
        exit 1
    fi

}

########################################################################################################################
# MAIN FUNCTION                                                                                                        #
########################################################################################################################

# Main Function
function main() {
    read_configuration
    set_configuration_parameters
    create_build_mount_dir
    create_entrypoint_script
    run_build
}

# Calling main function
main

######
# END#
######

echo "${_NOTE_CLR}"
#echo $AWS_ACCESS_KEY_ID
#echo $AWS_SECRET_ACCESS_KEY
#echo $AWS_SESSION_TOKEN
#echo $AWS_DEFAULT_REGION
echo "END"
echo "${_NORMAL_CLR}"
