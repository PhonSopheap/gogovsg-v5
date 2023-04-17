module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "gogov"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Create ECR repository
resource "aws_ecr_repository" "gogovsg_testing" {
  name                 = "gogov"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Create s3 bucket
resource "aws_s3_bucket" "go-bucket" {
  bucket = "go-buckets"
}

resource "aws_s3_bucket_acl" "acl" {
  bucket = aws_s3_bucket.go-bucket.id
  acl    = "private"
}

# Create db subnet group with public subnet
resource "aws_db_subnet_group" "gogov_db_subnet_group" {
  name       = "gogov-db-subnet-group"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_security_group" "rds" {
  name   = "gogov_rds"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_parameter_group" "postgresdb" {
  name   = "postgresdb"
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

# Provision the RDS instance
resource "aws_db_instance" "postgres_db" {
  identifier             = "postgresdb"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "14.1"
  username               = var.user
  password               = var.password
  db_subnet_group_name   = aws_db_subnet_group.gogov_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgresdb.name
  publicly_accessible    = true
  skip_final_snapshot    = true
}

# Create a subnet group for the Redis cluster
resource "aws_elasticache_subnet_group" "cache_subnet_group" {
  name       = "gogov-redis-subnet-group"
  subnet_ids = module.vpc.public_subnets
}

# Create a security group for the Redis cluster
resource "aws_security_group" "redis_security_group" {
  name_prefix = "gogov-redis"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Redis cluster
resource "aws_elasticache_cluster" "redis_cluster" {
  cluster_id             = "gogov-redis"
  engine                 = "redis"
  node_type              = "cache.t3.micro"
  num_cache_nodes        = 1
  parameter_group_name   = "default.redis7"
  security_group_ids     = [aws_security_group.redis_security_group.id]
  subnet_group_name      = aws_elasticache_subnet_group.cache_subnet_group.name
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = "go-testing"
  description = "for go project testing"
}

resource "aws_elastic_beanstalk_environment" "env" {
  name                = "go-testing-env"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2 v3.5.6 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     =  "aws-elasticbeanstalk-ec2-role"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.medium"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = module.vpc.vpc_id
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "${module.vpc.public_subnets[0]}, ${module.vpc.public_subnets[1]}, ${module.vpc.public_subnets[2]}"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "API_KEY_SALT"
    value     = "$$2b$$10$$9rBKuE4Gb5ravnvP4xjoPu"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "ASSET_VARIANT"
    value     = "gov"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "NODE_ENV"
    value     = "production"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "AWS_S3_BUCKET"
    value     = "go-buckets"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_URI" # postgresql rui
    value     = "postgres://${aws_db_instance.postgres_db.username}:${aws_db_instance.postgres_db.password}@${aws_db_instance.postgres_db.endpoint}/postgres"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "REPLICA_URI" # postgresql replica rui
    value     = "postgres://${aws_db_instance.postgres_db.username}:${aws_db_instance.postgres_db.password}@${aws_db_instance.postgres_db.endpoint}/postgres"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "OG_URL" # Original url like https://go.gov.sg
    value     = "https://go.devopsdemo.us"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "REDIS_OTP_URI"
    value     = "redis://gogov-redis.jv9xdv.0001.use1.cache.amazonaws.com:6379"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "REDIS_REDIRECT_URI"
    value     = "redis://gogov-redis.jv9xdv.0001.use1.cache.amazonaws.com:6379"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "REDIS_SAFE_BROWSING_URI"
    value     = "redis://gogov-redis.jv9xdv.0001.use1.cache.amazonaws.com:6379"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "REDIS_SESSION_URI"
    value     = "redis://gogov-redis.jv9xdv.0001.use1.cache.amazonaws.com:6379"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "REDIS_STAT_URI"
    value     = "redis://gogov-redis.jv9xdv.0001.use1.cache.amazonaws.com:6379"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SESSION_SECRET" # It could be any thing
    value     = "anything"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SES_HOST" # Simple email service on aws
    value     = "email-smtp.us-east-1.amazonaws.com"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SES_PASS" # Simple email service on aws
    value     = var.ses_pass
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SES_PORT" # Simple email service on aws
    value     = "587"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SES_USER" # Simple email service on aws
    value     = var.ses_user
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "VALID_EMAIL_GLOB_EXPRESSION"
    value     = "*@gmail.com"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "ROTATED_LINKS"
    value     = "whatsapp,passport,dgc,mptc"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "LOGIN_MESSAGE"
    value     = "Your OTP might take awhile to get to you."
  }
}