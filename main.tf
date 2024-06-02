provider "aws" {
  region = "us-east-1"
}

resource "aws_codecommit_repository" "revhire-job-repository" {
  repository_name = "revhire-job-repository"
  description     = "A revhire job-repository on AWS CodeCommit"
}

resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-service-role-for-job"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
    }]
  })
}

data "aws_codecommit_repository" "revhire-job-repository" {
  repository_name = aws_codecommit_repository.revhire-job-repository.repository_name
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "codecommit:GitPull"
        ]
        Resource = data.aws_codecommit_repository.revhire-job-repository.arn
      },
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:ssm:us-east-1:590183890913:parameter/ACCESS_KEY_ID",
          "arn:aws:ssm:us-east-1:590183890913:parameter/SECRET_ACCESS_KEY"
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "ecr-public:GetAuthorizationToken",
          "sts:GetServiceBearerToken"  # Added permission here
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "eks:DescribeCluster",
          "eks:GetToken"
        ]
        Resource = "arn:aws:eks:us-east-1:590183890913:cluster/revhire-cluster"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:ListFargateProfiles",
          "eks:DescribeFargateProfile"
        ]
        Resource = "*"
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "AWSEC2ContainerRegistryFullAccess" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}
resource "aws_iam_role_policy_attachment" "codebuild_s3_full_access" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_codepipeline_approver_access" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineApproverAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_codepipeline_custom_action_access" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineCustomActionAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_ssm_automation_role" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
}

resource "aws_iam_role_policy_attachment" "codebuild_ssm_full_access" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_codebuild_project" "revhire-job-build" {
  name          = "revhire-job-build"
  description   = "Build project for revhire-job application"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0"
    type                        = "LINUX_CONTAINER"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = "public.ecr.aws/m1n3x7n9/revhire-job-ecr-repo"
    }
    environment_variable {
      name  = "EKS_CLUSTERNAME"
      value = "revhire-cluster"
    }

    environment_variable {
      name  = "TAG"
      value = "latest"
    }
  }

  source {
    type            = "CODECOMMIT"
    location        = aws_codecommit_repository.revhire-job-repository.clone_url_http
    buildspec       = "buildspec.yaml"
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/revhire-job-build"
      stream_name = "build-log"
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "codecommit:GitPull",
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds",
          "s3:*",
          "iam:PassRole"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_codecommit_poweruser" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeCommitPowerUser"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codecommit_fullaccess" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeCommitFullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codebuild_adminaccess" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codebuild_developeraccess" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "revhire-job-codepipeline-artifacts"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "codepipeline_bucket_policy" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Action = "s3:*",
        Resource = [
          "${aws_s3_bucket.codepipeline_bucket.arn}",
          "${aws_s3_bucket.codepipeline_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codepipeline" "revhire_job_pipeline" {
  name     = "revhire-job-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_bucket.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = aws_codecommit_repository.revhire-job-repository.repository_name
        BranchName     = "master"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.revhire-job-build.name
      }
    }
  }
}
