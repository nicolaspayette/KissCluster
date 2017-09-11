#!/bin/bash

REGION=$1
CLUSTERNAME=$2
HOME_DIR=$3

set -e

NODESTABLE="kissc_nodes_${CLUSTERNAME}"
QUEUESTABLE="kissc_queues_${CLUSTERNAME}"
JOBSTABLE="kissc_jobs_${CLUSTERNAME}"


S3_job_envelope_script=`aws dynamodb --region ${REGION} get-item --table-name kissc_clusters --key '{"clustername":{"S":"'"${CLUSTERNAME}"'"}}' | jq -r ".Item.S3_job_envelope_script.S"`
S3_LOCATION_master=`aws dynamodb --region ${REGION} get-item --table-name kissc_clusters --key '{"clustername":{"S":"'"${CLUSTERNAME}"'"}}' | jq -r ".Item.S3_folder.S"
CLUSTERDATE=`aws dynamodb --region ${REGION} get-item \
    --table-name kissc_clusters \
    --key '{"clustername":{"S":"'"${CLUSTERNAME}"'"}}' \
    | jq -r ".Item.date.S"`

echo "Date of the cluster ${CLUSTERNAME} creation: ${CLUSTERDATE}"







echo "S3_LOCATION_master ${S3_LOCATION_master}"


NODEID=`aws dynamodb --region ${REGION} update-item \
    --table-name kissc_clusters \
    --key '{"clustername":{"S":"'"${CLUSTERNAME}"'"}}' \
    --update-expression "SET nodeid = nodeid + :incr" \
    --expression-attribute-values '{":incr":{"N":"1"}}' \
    --return-values UPDATED_NEW | jq -r ".Attributes.nodeid.N"`

createddate=$(date '+%Y%m%dT%H%M%SZ')


echo "Starting cluster node with nodeid: ${NODEID} Node creation date: ${createddate}"

NODEID_F=N"$(printf "%05d" $NODEID)"

mkdir -p ${HOME_DIR}
printf ${NODEID} > ${HOMEDIR}/node.id
aws s3 --region ${REGION} cp ${S3_job_envelope_script} ${HOME_DIR}/job_envelope.sh
chmod +x ${HOME_DIR}/job_envelope.sh


hostname=`curl -s http://169.254.169.254/latest/meta-data/public-hostname`
ip=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`
ami_id=`curl -s http://169.254.169.254/latest/meta-data/ami-id`
instance_id=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
instance_type=`curl -s http://169.254.169.254/latest/meta-data/instance-type`
iam_profile=`curl -s http://169.254.169.254/latest/meta-data/iam/info | jq -r ".InstanceProfileArn" 2>/dev/null`
if [[ -z ${iam_profile} ]]; then
   iam_profile="-"
fi
az=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
security_groups=`curl -s http://169.254.169.254/latest/meta-data/security-groups`
if [[ -z ${security_groups} ]]; then
   security_groups="-"
fi

echo "Node hostname: ${hostname}"
echo "Node ip: ${ip}"
echo "Node ami_id: ${ami_id}"
echo "Node instance_id: ${instance_id}"
echo "Node instance_type: ${instance_type}"
echo "Node iam_profile: ${iam_profile}"
echo "Node availability zone: ${az}"
echo "Configured security groups: ${security_groups}"

NPROC=`nproc`
logfile="${HOME_DIR}/log/${NODEID_F}_${createddate}.log.txt"

echo "Number of available vCPU cores: ${NPROC}"

echo "Node information will be written to DynamoFB table: ${NODESTABLE}"
res=`aws dynamodb --region ${REGION} put-item --table-name ${NODESTABLE} \
	--item '{"nodeid":{"N":"'${NODEID}'"},"nodedate":{"S":"'${createddate}'"},\
			"clusterdate":{"S":"'${CLUSTERDATE}'"},\
			"nproc":{"S":"'${NPROC}'"},"logfile":{"S":"'${logfile}'"},\
			"hostname":{"S":"'${hostname}'"},\
			"ip":{"S":"'${ip}'"},"ami_id":{"S":"'${ami_id}'"},\
			"instance_id":{"S":"'${instance_id}'"},\
			"instance_type":{"S":"'${instance_type}'"},\
			"iam_profile":{"S":"'${iam_profile}'"},\
			"az":{"S":"'${az}'"},\
			"security_groups":{"S":"'${security_groups}'"}}' `

nohup seq 1 100000000 | xargs --max-args=1 --max-procs=$NPROC bash ${HOME_DIR}/job_envelope.sh "${CLUSTERNAME}" "${REGION}" "${NODEID}" "${S3_LOCATION_master}" "${HOME_DIR}" "${CLUSTERDATE}" &>> $logfile &

echo "Node ${NODEID} has been successfully started."
echo "In order to terminate computations on this node look for the xargs process and kill it (pkill -f xargs)"



