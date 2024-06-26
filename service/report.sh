#!/bin/bash
sudo /usr/bin/nvidia-bug-report.sh
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
instance=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id)
echo $instance > instance.txt
echo "$(date --utc +%F\ %T\ %Z)" >> instance.txt
tar -czf $instance.tar.gz instance.txt nvidia-bug-report.log.gz
aws s3 cp $instance.tar.gz s3://stability-aws/
# presign url for case, one week validity
url=$(aws s3 presign s3://stability-aws/$instance.tar.gz --expires-in 604800) >> /fsx/shared/debug.log
# open support case
caseid=$(aws support create-case \
    --category-code "instance-issue" \
    --cc-email-addresses "devops@stability.ai" \
    --communication-body "Our automated scripts detected and isolated an instance that presents degraded GPU performance. Please refer to the debug report available at $url" \
    --issue-type "technical" \
    --language "en" \
    --service-code "amazon-elastic-compute-cloud-linux" \
    --severity-code "high" \
    --subject "Node detected with underperforming GPU" | jq -r '.caseID')
echo "Support case open under id $caseid" >> /fsx/shared/debug.log
# capture the node
sleep 3000000

# place this file in /opt/slurm/sbin