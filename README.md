# AWS ECS autoscaling image

[`ndegardin/aws-ecs-autoscaling`](https://hub.docker.com/r/ndegardin/aws-ecs-autoscaling/)

An container that provides an autoscaling mechanism for **AWS ECS clusters**.

The point is to always have room to run a container inside the **ECS cluster**, while keeping costs low and avoiding manual operations.

This container is meant to be run very regularly (each five minutes or less) on each **EC2 instance** of the **ECS cluster**. It provides additional **Cloudwatch** metrics that can be used to configure the scaling rules of an **autoscaling group**, and uses an instance termination protection mechanism to prevent stopping running tasks when scaling in.

## Concept

The concept of this autoscaling mechanism is that the most important metric to run containers on the **autoscaling group** of an **ECS cluster** is the available memory. An **ECS service** has its own scaling policy, and can be configured to spawn a new container if its CPU gets overloaded. But the **ECS cluster** has to ensure there's always enough available memory to launch this new container, possibly at once.

Consequently, this mechanism takes the biggest hard/soft memory limit from the **ECS Task definitions** as a reference, considering that the **ECS cluster** should be able to run this container at least once on a free **EC2 instance**.
The metrics can then be adjusted as multiples of this value, which we call **ContainerSlots**.

### Scaling in and out

Two **CloudWatch** alarms have to be configured to define the minimum and maximum number of **ContainerSlots** that should be available, and the **autoscaling** group to add or remove an **EC2 instance** when these treshold are exceeded.

The available **ContainerSlots** ensure that there's always enough memory to start a container instantly in case of need. The more there are, the more containers can be started instantly at the same time.

### Scaling out protection

This container also protects its **EC2 instance** from being removed by the **autoscaling group** if containers are still running. Indeed, a container may be running an important task or a service may run only once instance, and it's better to avoid any outage due to an arbitrary **autoscaling** operation.

## Features

When run, this container sends the following metrics describing the **EC2 instance** on which it's running to **Cloudwatch**:

- `Custom/ECS - MaxContainerSize`: the biggest hard/soft memory limit from all the container definitions of this **ECS cluster**
- `Custom/ECS - RunningTaskCount`: the number of containers running on this instance
- `Custom/ECS - MemoryAvailable`: the available memory to run containers
- `Custom/ECS - ContainerSlots`: the number of containers the size of `MaxContainerSize` that could run on this instance (according to `MemoryAvailable`)
- `Custom/ECS - EmptyInstance`: 0 if a container is running, 1 if no container is running

This container also protects the **EC2 instance** on which it's running from termination if `EmptyInstance` is equal to 0, and removes this protection if `EmptyInstance` is equal to 1.

## Usage

    docker run degardinn/aws-ecs-autoscaling

This command should be run as a scheduled task, we recommend running it every 5 minutes or less. It can be add as a _CRON_ task by executing this command:

    echo "*/5 * * * * docker run ndegardin/aws-ecs-autoscaling" | crontab -

See **EC2 instances User Data** for the right place where to put this command.

## Notes

### Requirements

The right **AWS policys** has to be set to allow the **EC2 instances** of the **ECS cluster** to write metrics into **Cloudwatch** and to alter the **EC2 termination protection** state.

The minimal number of **ContainerSlots** configured in the **Cloudwatch alarms** must be at least 1.

The **EC2 instances** defined in the **Autoscaling group launch configuration** must have more memory than **MaxContainerSize**.

Each time a service is added to the **ECS cluster**, it must be added with the **binpack** repartition rule, to avoid spreading containers over all the instances of the scaling group (which will prevent **EC2 instances** from being terminated).

### Considerations

A container doesn't necesarily runs instantly. It may have to be downloaded if the **EC2 instance** on which it's running has never done so (and has never put it in its cache), or if the container was updated. Given that this mechanism often terminates and spawn instances, downloading a container again may happen quite frequently.

It is recommended to watch the metrics and to adjust the values of the **Cloudwatch alarms**, mainly the difference between the minimum and maximum number of **ContainerSlots** to prevent the number of **EC2 instances** from dancing too much (which will reduce the phenomena of instances with an empty cache).

### Cloudwatch dashboard

A **Cloudwatch dashboard** could help figuring out what happens on the **ECS cluster**.

We recommend creating at least

- a **line graph** with:
  - `Custom/ECS - RunningTasksCount`: sum, on the left Y axis
  - `Custom/ECS - ContainerSlots`: sum, on the left Y axis
  - `Custom/ECS - EmptyInstance`: sum, on the right Y axis
  - `AWS/Autoscaling - GroupInServiceInstances`: maximum, on the right Y axis
- a **number graph**, with `Custom/ECS - MaxContainerSize`: maximum
