#!/bin/bash

HOST_IP=$(ip route|head -n 1|sed -r 's/default via ([0-9.]+).*$/\1/')

# Initial parameters
clusterName=$(curl -s "http://$HOST_IP:51678/v1/metadata" | jq -r ".Cluster")
instanceArn=$(curl -s "http://$HOST_IP:51678/v1/metadata" | jq -r ".ContainerInstanceArn")
region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
instanceInfo=$(aws ecs describe-container-instances --cluster $clusterName --container-instances $instanceArn --region $region)

# Settings
metricNameSpace="Custom/ECS"
metricDimension="ClusterName"

# Metrics
maxContainerSize=$(aws ecs list-task-definitions --region $region | jq -r  '.taskDefinitionArns[]' | xargs -n 1 aws ecs describe-task-definition --region $region --task-definition  | jq '.taskDefinition.containerDefinitions[]|[.memory//0, .memoryReservation//0]|max'|sort -nr|head -n1)
memoryAvailableForContainers=$(echo $instanceInfo|jq '.containerInstances[].remainingResources[] | select(.name == "MEMORY") | .integerValue')
runningTasks=$(aws ecs describe-container-instances --cluster $clusterName --container-instances $instanceArn --region $region | jq '.containerInstances[].runningTasksCount')
containerSlotsAvailable=$(($memoryAvailableForContainers / $maxContainerSize))
noContainersRunning=$(($runningTasks < 1))
echo "Max container size: $maxContainerSize, Available memory: $memoryAvailableForContainers, Containers running: $runningTasks, Container slots available: $containerSlotsAvailable, Empty instance: $noContainersRunning"

# Termination protection on/off
instanceId=$(echo $instanceInfo|jq -r '.containerInstances[].ec2InstanceId')
asgInfo=$(aws autoscaling describe-auto-scaling-instances --region $region --instance-ids $instanceId)
asgId=$(echo $asgInfo|jq -r '.AutoScalingInstances[].AutoScalingGroupName')
asgProtection=$(echo $asgInfo|jq -r '.AutoScalingInstances[].ProtectedFromScaleIn')

if [ $noContainersRunning == 1 ] && [ $asgProtection == true ]; then
    aws autoscaling set-instance-protection --region $region --instance-ids $instanceId --auto-scaling-group-name $asgId --no-protected-from-scale-in
    echo "Disabling scale-in protection"
elif  [ $noContainersRunning == 0 ] && [ $asgProtection == false ]; then
    aws autoscaling set-instance-protection --region $region --instance-ids $instanceId --auto-scaling-group-name $asgId --protected-from-scale-in
    echo "Enabling scale-in protection"
fi

aws cloudwatch put-metric-data --namespace $metricNameSpace --metric-name "MemoryAvailable" --dimensions "$metricDimension=$clusterName" --unit "None" --value "$memoryAvailableForContainers" --region $region
aws cloudwatch put-metric-data --namespace $metricNameSpace --metric-name "MaxContainerSize" --dimensions "$metricDimension=$clusterName" --unit "None" --value "$maxContainerSize" --region $region
aws cloudwatch put-metric-data --namespace $metricNameSpace --metric-name "ContainerSlots" --dimensions "$metricDimension=$clusterName" --unit "None" --value "$containerSlotsAvailable" --region $region
aws cloudwatch put-metric-data --namespace $metricNameSpace --metric-name "EmptyInstance" --dimensions "$metricDimension=$clusterName" --unit "None" --value "$noContainersRunning" --region $region
aws cloudwatch put-metric-data --namespace $metricNameSpace --metric-name "RunningTasksCount" --dimensions "$metricDimension=$clusterName" --unit "None" --value "$runningTasks" --region $region