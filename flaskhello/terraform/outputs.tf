output "ecs_cluster_name" {
    description = "ECS cluster name"
    value = aws_ecs_cluster.main.name
}

output "ec2_public_ip" {
    description = "Public IP of the EC2 host EC2 instance"
    value = aws_instance.ecs_host.public_ip
}

output "cloudwatch_log_group" {
    description = "CloudWatch log group name"
    value = aws_cloudwatch_log_group.flaskhello.name
}
