# Context
I want to develop a bash script, that will have two behaviors:

# Logic
1. If run with --test, it will run the function locally, but will have to receive the function name as an argument. For this scenario, it WILL NOT use docker to deploy it, unless --docker=True is passed as an argument. It will use functions-framework to run it locally. The name of the function would be taken from the dockerfile.

2. If run with --deploy, it will deploy the function to Google Cloud Run. 

For both scenarios, if a string with ".env" at the end is passed as an argument, will consider it as the path of a .env file, and will read it to get the values of the variables to be used in the deployment.

For the deploy scenario, it will create a secret for each variable in the .env file, and will use them in the deployment.

# Considerations
- Work only on cloud_run.sh
- At this moment, only work on test scenario
- Only work on cloud_run.sh
