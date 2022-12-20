#------------------------------------------------------------------------------
# AWS KMS Encryption Key
#------------------------------------------------------------------------------
resource "aws_kms_key" "encryption_key" {
  description         = "Sonar Encryption Key"
  is_enabled          = true
  enable_key_rotation = true

  tags = merge({
    Name = "${var.name_prefix}-sonar-kms-key"
  }, var.tags)
}

#------------------------------------------------------------------------------
# AWS RDS Subnet Group
#------------------------------------------------------------------------------
resource "aws_db_subnet_group" "db" {
  name       = "${var.name_prefix}-sonar-db-subnet-group"
  subnet_ids = var.private_subnets_ids

  tags = merge({
    Name = "${var.name_prefix}-sonar-aurora-db-subnet-group"
  }, var.tags)
}

# #------------------------------------------------------------------------------
# # AWS RDS Aurora Cluster
# #------------------------------------------------------------------------------
# resource "aws_rds_cluster" "aurora_db" {
#   depends_on = [aws_kms_key.encryption_key]

#   # Cluster
#   cluster_identifier     = "${var.name_prefix}-sonar-aurora-db"
#   vpc_security_group_ids = [aws_security_group.aurora_sg.id]
#   db_subnet_group_name   = aws_db_subnet_group.aurora_db_subnet_group.id
#   deletion_protection    = var.db_deletion_protection

#   # Encryption
#   storage_encrypted = true
#   kms_key_id        = aws_kms_key.encryption_key.arn

#   # Logs
#   #enabled_cloudwatch_logs_exports = ["audit", "error", "general"]
#   # Database
#   engine          = "aurora-postgresql"
#   engine_version  = local.sonar_db_engine_version
#   database_name   = local.sonar_db_name
#   master_username = local.sonar_db_username
#   master_password = local.sonar_db_password

#   # Backups
#   backup_retention_period = var.db_backup_retention_period
#   preferred_backup_window = "07:00-09:00"
#   skip_final_snapshot     = true
#   copy_tags_to_snapshot   = true
#   tags = merge({
#     Name = "${var.name_prefix}-sonar-aurora-db"
#   }, var.tags)
# }

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "5.2.1"

  identifier = local.sonar_db_name

  kms_key_id = aws_kms_key.encryption_key.arn

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = local.sonar_db_engine_version
  major_engine_version = local.sonar_db_major_engine_version
  family               = "postgres14" # DB parameter group
  instance_class       = "db.t3.micro"

  publicly_accessible = false

  allocated_storage     = 32
  max_allocated_storage = 128

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = local.sonar_db_name
  username = local.sonar_db_username
  password = local.sonar_db_password
  create_random_password = false
  port     = local.sonar_db_port

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db.id
  vpc_security_group_ids = [aws_security_group.db.id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = true

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = merge({
    Name = "${var.name_prefix}-sonar-db"
  }, var.tags)
}

# #------------------------------------------------------------------------------
# # AWS RDS Aurora Cluster Instances
# #------------------------------------------------------------------------------
# resource "aws_rds_cluster_instance" "aurora_db_cluster_instances" {
#   count                = coalesce(var.db_instance_number, length(var.private_subnets_ids))
#   identifier           = "${var.name_prefix}-aurora-db-instance-${count.index}"
#   cluster_identifier   = aws_rds_cluster.aurora_db.id
#   db_subnet_group_name = aws_db_subnet_group.aurora_db_subnet_group.id
#   engine               = "aurora-postgresql"
#   engine_version       = local.sonar_db_engine_version
#   instance_class       = local.sonar_db_instance_size
#   publicly_accessible  = false
#   tags = merge({
#     Name = "${var.name_prefix}-sonar-aurora-db-cluster-instances-${count.index}"
#   }, var.tags)
# }

#------------------------------------------------------------------------------
# AWS Security Groups - Allow traffic to Aurora DB only on PostgreSQL port and only coming from ECS SG
#------------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-sonar-db-sg"
  description = "Allow traffic to Aurora DB only on PostgreSQL port and only coming from ECS SG"
  vpc_id      = var.vpc_id
  ingress {
    protocol  = "tcp"
    from_port = local.sonar_db_port
    to_port   = local.sonar_db_port
    security_groups = [module.ecs_fargate.ecs_tasks_sg_id]
  }
  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge({
    Name = "${var.name_prefix}-sonar-db-sg"
  }, var.tags)
}
