# local-codebuild
Allows you to run CodeBuild Locally


## Requirements

| Tool    | Link                                                                   |
| ------- | ---------------------------------------------------------------------- |
| AWS CLI | https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html |
| jq      | https://stedolan.github.io/jq/                                         |
| wildq   | https://pypi.org/project/wildq/                                        |
| docker  | https://docs.docker.com/engine/install/                                |

# Note

This automation will create files temporarily in `/tmp/local-codebuild` directory.
Clean this directory to make space in /tmp.


# Supported BuildSpec Properties

```bash
phases:
  install:
    commands:
      - pip install -r requirements.txt
  build:
    commands:
      - aws sts get-caller-identity
```

# Supported Source
- local

# Upcoming Support for Source
- git