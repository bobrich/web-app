resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  name   = "lambda_policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = "${aws_secretsmanager_secret.github_token.arn}"
      }
    ]
  })
}

resource "aws_lambda_function" "web_app" {
  function_name = "web_app_lambda"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 10

  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  filename         = "lambda_function_payload.zip"
}



# S3 Bucket for CodePipeline artifacts
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "codepipeline-rrich" # Replace with a unique bucket name
}



# IAM Role for CodeBuild - with basic permissions for logs and S3 access
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        },
      },
    ]
  })

  inline_policy {
    name = "codebuild_policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "s3:PutObject",
            "s3:GetObject",
            "s3:GetObjectVersion",
            "iam:GetRole",
            "apigateway:GET",
            "secretsmanager:DescribeSecret"
          ],
          Effect = "Allow",
          Resource = "*"
        },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = "arn:aws:s3:::tfstate-rrich/*"
      },
    {
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::codepipeline-rrich/*",
      "arn:aws:s3:::codepipeline-rrich"
    ]
  },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = "arn:aws:s3:::tfstate-rrich"
      },
      {
        Effect = "Allow",
        Action = [
         "secretsmanager:GetSecretValue"
        ],
        Resource = "${aws_secretsmanager_secret.github_token.arn}"
        } 
      ]
    })
  }
}

# IAM Role for CodePipeline - with permissions for CodeBuild, Lambda, S3, and IAM pass role
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
      },
    ]
  })

  inline_policy {
    name = "codepipeline_policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "codebuild:StartBuild",
            "codebuild:BatchGetBuilds",
            "lambda:InvokeFunction",
            "s3:PutObject",
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:GetBucketVersioning"
          ],
          Effect = "Allow",
          Resource = "*"
        },
        {
          Action = "iam:PassRole",
          Effect = "Allow",
          Resource = "*",
          Condition = {
            StringEqualsIfExists = {
              "iam:PassedToService": [
                "codebuild.amazonaws.com",
                "lambda.amazonaws.com"
              ]
            }
          }
        }
      ]
    })
  }
}


resource "aws_codepipeline" "web_app_pipeline" {
  name     = "web-app-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  # CodePipeline artifact store
  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  # Required minimum of two stages: source and build
  stage {
    name = "Source"
    action {
      name     = "Source"
      category = "Source"
      owner    = "ThirdParty"
      provider = "GitHub"
      version  = "1"

      configuration = {
        Owner      = "bobrich"
        Repo       = "web-app"
        Branch     = "dev"
        OAuthToken = var.github_token
      }

      output_artifacts = [ 
       "source_output"
      ]
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
        ProjectName = "web-app-build"
      }
    }
  }

}
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "MyAPI"
  description = "API Gateway for Web Application"
}

resource "aws_api_gateway_resource" "my_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "path"
}

resource "aws_api_gateway_method" "my_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.my_api_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "my_api_integration" {
  integration_http_method = "GET"
  http_method = "GET"
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.my_api_resource.id
  #http_method = aws_api_gateway_method.my_api_method.http_method
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.web_app.invoke_arn
}

resource "aws_api_gateway_deployment" "my_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.my_api_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name  = "test"
}

output "api_gateway_invoke_url" {
  value       = aws_api_gateway_deployment.my_api_deployment.invoke_url
  description = "Invoke URL for API Gateway"
}

resource "aws_codebuild_project" "web_app_build" {
  name         = "web-app-build"
  description  = "Build project for the web application"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE" 
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0" 
    type         = "LINUX_CONTAINER"
    environment_variable {
      name  = "GITHUB_TOKEN"
      type  = "SECRETS_MANAGER"
      value = aws_secretsmanager_secret.github_token.id
    }
  }

  source {
    type            = "CODEPIPELINE"
    buildspec       = "buildspec.yml" 
  }
}

terraform {
  backend "s3" {
    bucket = "tfstate-rrich"
    key    = "web-app/state"
    region = "us-east-1"
  }
}

resource "aws_secretsmanager_secret" "github_token" {
  name = "my_github_token"
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id     = aws_secretsmanager_secret.github_token.id
  secret_string = var.github_token
}

