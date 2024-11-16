terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.75.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  access_key = "" # Add your access key
  secret_key = "" # Add your secret key
}

# VPC and Networking
resource "aws_vpc" "main-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main-vpc.id

  tags = {
    Name = "main-vpc-igw"
  }
}

resource "aws_route_table" "main-vpc-rt" {
  vpc_id = aws_vpc.main-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main-vpc-rt"
  }
}

# Public Subnets for ALB
resource "aws_subnet" "main-vpc-subnet" {
  vpc_id                  = aws_vpc.main-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "main-vpc-subnet-1"
  }
}

resource "aws_subnet" "main-vpc-subnet-2" {
  vpc_id                  = aws_vpc.main-vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "main-vpc-subnet-2"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main-vpc-subnet.id
  route_table_id = aws_route_table.main-vpc-rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.main-vpc-subnet-2.id
  route_table_id = aws_route_table.main-vpc-rt.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-security-group"
  }
}

resource "aws_security_group" "allow_web" {
  name        = "ec2-security-group"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }
}

# Application Load Balancer
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.main-vpc-subnet.id, aws_subnet.main-vpc-subnet-2.id]

  tags = {
    Name = "web-alb"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main-vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    timeout             = 5
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    unhealthy_threshold = 2
  }
}

# Memory and Disk Monitoring CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period             = "300"
  statistic          = "Average"
  threshold          = "80"
  alarm_description  = "Memory utilization above 80%"
  alarm_actions      = [aws_autoscaling_policy.scale_up.arn, aws_sns_topic.cloudwatch_alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "e-commerce-monitoring"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web_asg.name]
          ]
          period = 300
          region = "us-east-1"
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.web_alb.arn_suffix]
          ]
          period = 300
          region = "us-east-1"
          title  = "ALB Request Count"
        }
      }
    ]
  })
}

# Launch Template and Auto Scaling Group
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-template"
  image_id      = "ami-0f1a6835595fb9246"  # Amazon Linux 2 AMI ID
  instance_type = "t2.micro"
  key_name      = "main-key" 

  network_interfaces {
    associate_public_ip_address = true
    security_groups            = [aws_security_group.allow_web.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd wget unzip amazon-cloudwatch-agent
              
              # Configure CloudWatch agent
              cat > /opt/aws/amazon-cloudwatch-agent/bin/config.json <<'EOF_CW'
              {
                "metrics": {
                  "metrics_collected": {
                    "mem": {
                      "measurement": ["mem_used_percent"],
                      "metrics_collection_interval": 60
                    },
                    "disk": {
                      "measurement": ["disk_used_percent"],
                      "metrics_collection_interval": 60
                    }
                  }
                }
              }
              EOF_CW
              
              # Start CloudWatch agent
              sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
              sudo systemctl start amazon-cloudwatch-agent
              
              # Install web server and website
              sudo systemctl start httpd
              sudo systemctl enable httpd
              cd /tmp
              wget https://www.free-css.com/assets/files/free-css-templates/download/page260/e-store.zip
              unzip -o e-store.zip
              sudo cp -r ecommerce-html-template/* /var/www/html/
              sudo chmod -R 755 /var/www/html/
              sudo systemctl restart httpd
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-server"
    }
  }
}

# Update IAM role to allow CloudWatch agent
resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "cloudwatch_policy"
  role = aws_iam_role.ec2_dynamodb_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:CreateLogGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity    = 2
  max_size           = 4
  min_size           = 1
  target_group_arns  = [aws_lb_target_group.web_tg.arn]
  vpc_zone_identifier = [aws_subnet.main-vpc-subnet.id, aws_subnet.main-vpc-subnet-2.id]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-server"
    propagate_at_launch = true
  }
}

# IAM Role and Instance Profile
resource "aws_iam_role" "ec2_dynamodb_access" {
  name = "ec2_dynamodb_access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_dynamodb_profile"
  role = aws_iam_role.ec2_dynamodb_access.name
}

# CloudWatch Alarms and Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "cloudwatch_alarms" {
  name = "cloudwatch-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.cloudwatch_alarms.arn
  protocol  = "email"
  endpoint  = "EMAIL HERE"
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = "70"
  alarm_description  = "Scale up if CPU utilization is above 70% for 10 minutes"
  alarm_actions      = [aws_autoscaling_policy.scale_up.arn, aws_sns_topic.cloudwatch_alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "low-cpu-utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = "30"
  alarm_description  = "Scale down if CPU utilization is below 30% for 10 minutes"
  alarm_actions      = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

# Outputs
output "website_alb_url" {
  description = "URL of the e-store website through ALB"
  value       = "http://${aws_lb.web_alb.dns_name}"
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_asg.name
}