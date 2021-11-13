init:
	pipenv --python 3.8
	pipenv install --dev

# Command to run everytime you make changes to verify everything works
dev: flake lint test

# Verifications to run before sending a pull request
pr: init dev

SAM_TEMPLATE ?= template.yaml
TRANSFORM_TEMPLATE ?= transform-template.yaml
TRANSFORM_STACKNAME ?= codepipeline-cfn-transform
ENV ?= ${USER}
BUILD_STACKNAME = codepipeline-build-$(ENV)
DEPLOY_STACKNAME = codepipeline-deploy-$(ENV)
AWS_REGION ?= $(shell aws configure get region)
DEPLOY_ACCOUNTS ?= "355364402302,641494176294"
BUILD_ACCOUNT ?= "346402060170"

check_profile:
	# Make sure we have a user-scoped credentials profile set. We don't want to be accidentally using the default profile
	@aws configure --profile ${AWS_PROFILE} list 1>/dev/null 2>/dev/null || (echo '\nMissing AWS Credentials Profile called '${AWS_PROFILE}'. Run `aws configure --profile ${AWS_PROFILE}` to create a profile called '${AWS_PROFILE}' with creds to your personal AWS Account'; exit 1)

build:
	$(info Building application)
	sam build --use-container --parallel --template ${SAM_TEMPLATE}

validate:
	$(info linting SAM template)
	$(info linting CloudFormation)
	@cfn-lint template.yaml
	$(info validating SAM template)
	@sam validate

deploy-transform: validate
	$(info Deploying string transform stack)
	sam deploy --stack-name $(TRANSFORM_STACKNAME) --region ${AWS_REGION} --resolve-s3 --template $(TRANSFORM_TEMPLATE)

deploy-build: validate build
	$(info Deploying build stack for environment $(ENV))
	sam deploy \
		--stack-name $(BUILD_STACKNAME) \
		--region ${AWS_REGION} \
		--resolve-s3 \
		--parameter-overrides \
			DeployAccounts=$(DEPLOY_ACCOUNTS) \
			DevPipelineExecutionRole=arn:aws:iam::355364402302:role/codepipeline-deploy-prime-PipelineExecutionRole-1RJELCC4B0ZZS \
			DevCodeBuildServiceRole=arn:aws:iam::355364402302:role/codepipeline-deploy-prime-CodeBuildServiceRole-204VUL63KP2Y \
			DevCfnExecutionRole=arn:aws:iam::355364402302:role/codepipeline-deploy-prime-CloudFormationExecutionR-1S70T54200FFL \
			ProdPipelineExecutionRole=arn:aws:iam::641494176294:role/codepipeline-deploy-prime-PipelineExecutionRole-Y49S9AATMRB9 \
			ProdCodeBuildServiceRole=arn:aws:iam::641494176294:role/codepipeline-deploy-prime-CodeBuildServiceRole-1IUYX5T367ELN \
			ProdCfnExecutionRole=arn:aws:iam::641494176294:role/codepipeline-deploy-prime-CloudFormationExecutionR-1UCVUPIMOBDQH \
			BuildPipeline=true

deploy-deploy: validate build
	$(info Deploying deploy stack for environment $(ENV))
	sam deploy \
		--stack-name $(DEPLOY_STACKNAME) \
		--region ${AWS_REGION} \
		--resolve-s3 \
		--parameter-overrides \
			BuildPipeline=false \
			BuildAccount=$(BUILD_ACCOUNT)  \
			ArtifactsBucketArn=arn:aws:s3:::codepipeline-build-prime-artifactsbucket-1a2aazfgk38hj \
			ArtifactsBucketKmsKeyArn=arn:aws:kms:us-east-1:346402060170:key/mrk-5f536b59c2c94f6b84649a25e080640f\
			ImageRepositoryArn=arn:aws:ecr:us-east-1:346402060170:repository/codepipeline-build-prime-imagerepository-fjwybjdbsgxz
 \
			BuildPipeline=false

describe:
	$(info Describing stack)
	@aws cloudformation describe-stacks --stack-name $(STACKNAME) --output table --query 'Stacks[0]'

outputs:
	$(info Displaying stack outputs)
	@aws cloudformation describe-stacks --stack-name $(STACKNAME) --output table --query 'Stacks[0].Outputs'

parameters:
	$(info Displaying stack parameters)
	@aws cloudformation describe-stacks --stack-name $(STACKNAME) --output table --query 'Stacks[0].Parameters'

delete:
	$(info Delete stack)
	@sam delete --stack-name $(STACKNAME)

function:
	$(info creating function: ${F})
	mkdir -p src/handlers/${F}
	touch src/handlers/${F}/__init__.py
	touch src/handlers/${F}/function.py
	mkdir -p tests/{unit,integration}/src/handlers/${F}
	touch tests/unit/src/handlers/${F}/__init__.py
	touch tests/unit/src/handlers/${F}/test_handler.py
	touch tests/integration/src/handlers/${F}/__init__.py
	touch tests/integration/src/handlers/${F}/test_handler.py
	echo "-e src/common/" > src/handlers/${F}/requirements.txt
	touch data/events/${F}-{event,msg}.json

unit-test:
	$(info running unit tests)
	# Integration tests don't need code coverage
	pipenv run pytest tests/unit

integ-test:
	$(info running integration tests)
	# Integration tests don't need code coverage
	pipenv run pytest tests/integration

test:
	$(info running tests)
	# Run unit tests
	# Fail if coverage falls below 95%
	pipenv run test

flake8:
	$(info running flake8 on code)
	# Make sure code conforms to PEP8 standards
	pipenv run flake8 src
	pipenv run flake8 tests/unit tests/integration

pylint:
	$(info running pylint on code)
	# Linter performs static analysis to catch latent bugs
	pipenv run lint --rcfile .pylintrc src

lint: pylint flake8

clean:
	$(info cleaning project)
	# remove sam cache
	rm -rf .aws-sam
