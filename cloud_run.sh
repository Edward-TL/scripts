#!/bin/bash

REQUIRED_KEYS=("PROJECT_ID" "REGION" "SERVICE_NAME" "IMAGE_NAME")

function handle_secret_value() {
    local KEY_NAME=$1
    local RAW_VALUE=$2

    # Check if value is a path to a .json file
    if [[ "$RAW_VALUE" == *.json ]]; then
        if [ -f "$RAW_VALUE" ]; then
            # Read file content and create/update secret
            echo "Loading secret $KEY_NAME from file $RAW_VALUE..."
            gcloud secrets create "$KEY_NAME" --replication-policy="automatic" 2>/dev/null
            echo -n "$(cat "$RAW_VALUE")" | gcloud secrets versions add "$KEY_NAME" --data-file=- --quiet
            echo "$KEY_NAME=$KEY_NAME:latest"
        else
            echo "Error: File $RAW_VALUE not found." >&2
            exit 1
        fi
    else
        # Treat as raw string/dictionary format
        echo "Uploading raw secret for $KEY_NAME..."
        gcloud secrets create "$KEY_NAME" --replication-policy="automatic" 2>/dev/null
        echo -n "$RAW_VALUE" | gcloud secrets versions add "$KEY_NAME" --data-file=- --quiet
        echo "$KEY_NAME=$KEY_NAME:latest"
    fi
}

# --- Arguments & Env Loading ---
FLAG=$1
FOLDER_PATH=${2:-"."}
ENV_PATH="$FOLDER_PATH/.env"

if [ ! -f "$ENV_PATH" ]; then
    echo "Error: no .env file. Required: ${REQUIRED_KEYS[*]}"; exit 1
fi

export $(grep -v '^#' "$ENV_PATH" | xargs)

# --- Process Secrets Logic ---
FINAL_SECRETS_LIST=""

if [ ! -z "$GOOGLE_CREDENTIALS" ]; then
    RESULT=$(handle_secret_value "GOOGLE_CREDENTIALS" "$GOOGLE_CREDENTIALS")
    FINAL_SECRETS_LIST+="$RESULT"
fi

if [ ! -z "$SECRETS" ]; then
    # Add comma if list isn't empty
    [[ ! -z "$FINAL_SECRETS_LIST" ]] && FINAL_SECRETS_LIST+=","
    RESULT=$(handle_secret_value "APP_SECRETS" "$SECRETS")
    FINAL_SECRETS_LIST+="$RESULT"
fi

case $FLAG in
    --test)
        docker build -t "$IMAGE_NAME:local" "$FOLDER_PATH"
        docker run -p 8080:8080 --env-file "$ENV_PATH" "$IMAGE_NAME:local"
        ;;
    --deploy)
        gcloud builds submit "$FOLDER_PATH" --tag "gcr.io/$PROJECT_ID/$IMAGE_NAME"
        gcloud run deploy "$SERVICE_NAME" \
            --image "gcr.io/$PROJECT_ID/$IMAGE_NAME" \
            --region "$REGION" \
            --project "$PROJECT_ID" \
            ${FINAL_SECRETS_LIST:+--set-secrets="$FINAL_SECRETS_LIST"} \
            --allow-unauthenticated
        ;;
    *)
        echo "Usage: cloud_run [--test|--deploy] [path]"; exit 1
        ;;
esac