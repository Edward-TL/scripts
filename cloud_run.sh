#!/bin/bash

# Configuration: Define required keys for the .env file
REQUIRED_KEYS=("PROJECT_ID" "REGION" "SERVICE_NAME" "IMAGE_NAME")

function show_error_and_exit {
    echo "Error: no .env file found in $1"
    echo "Please ensure the following keys are defined in your .env file:"
    for key in "${REQUIRED_KEYS[@]}"; do
        echo "  - $key"
    done
    exit 1
}

# 1. Capture arguments
FLAG=$1
FOLDER_PATH=${2:-"."} # Default to current directory if not provided

# 2. Check for .env file
ENV_PATH="$FOLDER_PATH/.env"

if [ ! -f "$ENV_PATH" ]; then
    show_error_and_exit "$FOLDER_PATH"
fi

# 3. Load environment variables
export $(grep -v '^#' "$ENV_PATH" | xargs)

# 4. Logic based on flags
case $FLAG in
    --test)
        echo "--- Starting Local Test for $SERVICE_NAME ---"
        # Build the local image
        docker build -t "$IMAGE_NAME:local" "$FOLDER_PATH"
        
        # Run the container locally (assumes port 8080)
        echo "Running on http://localhost:8080"
        docker run -p 8080:8080 --env-file "$ENV_PATH" "$IMAGE_NAME:local"
        ;;

    --deploy)
        echo "--- Deploying $SERVICE_NAME to Cloud Run ---"
        # Submit build to Google Container Registry/Artifact Registry
        gcloud builds submit "$FOLDER_PATH" --tag "gcr.io/$PROJECT_ID/$IMAGE_NAME"
        
        # Deploy to Cloud Run
        gcloud run deploy "$SERVICE_NAME" \
            --image "gcr.io/$PROJECT_ID/$IMAGE_NAME" \
            --platform managed \
            --region "$REGION" \
            --allow-unauthenticated \
            --project "$PROJECT_ID"
        ;;

    *)
        echo "Usage: cloud_run [--test|--deploy] [project_path]"
        exit 1
        ;;
esac