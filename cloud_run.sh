#!/bin/bash

# Ensure script has execute permissions: chmod +x cloud_run.sh

# --- Global Variables ---
MODE=""
USE_DOCKER=false
ENV_FILE=""
FUNCTION_NAME=""
REQUIRED_KEYS=("PROJECT_ID" "REGION" "SERVICE_NAME" "IMAGE_NAME")

# --- Argument Parsing ---
for arg in "$@"; do
    case $arg in
        --test)
            MODE="test"
            ;;
        --deploy)
            MODE="deploy"
            ;;
        --docker=True)
            USE_DOCKER=true
            ;;
        *.env)
            ENV_FILE="$arg"
            ;;
        *)
            if [[ "$arg" != --* ]]; then
                FUNCTION_NAME="$arg"
            fi
            ;;
    esac
done

# --- Context Determination ---
if [ -n "$ENV_FILE" ]; then
    # If .env is provided, use its directory as context
    CONTEXT_DIR=$(dirname "$ENV_FILE")
    # Resolve to absolute path
    CONTEXT_DIR=$(cd "$CONTEXT_DIR" && pwd)
else
    CONTEXT_DIR=$(pwd)
fi

echo "Working directory: $CONTEXT_DIR"

# --- Helper Functions ---

handle_secret_value() {
    local KEY_NAME=$1
    local RAW_VALUE=$2
    local PROJECT=$3
    
    # Check if value is empty
    if [ -z "$RAW_VALUE" ]; then
        return
    fi

    echo "Processing secret: $KEY_NAME" >&2
    
    # Create secret if not exists
    gcloud secrets create "$KEY_NAME" --replication-policy="automatic" --project="$PROJECT" 2>/dev/null || true
    
    # Add version
    echo -n "$RAW_VALUE" | gcloud secrets versions add "$KEY_NAME" --data-file=- --project="$PROJECT" --quiet > /dev/null
    
    echo "$KEY_NAME=$KEY_NAME:latest"
}

load_env_vars() {
    local file=$1
    if [ -f "$file" ]; then
        echo "Loading variables from $file"
        set -a
        source "$file"
        set +a
    else
        echo "Warning: .env file '$file' not found."
    fi
}

# --- Execution Logic ---

# Change to context directory to ensure builds/runs work as expected
cd "$CONTEXT_DIR" || exit 1

if [ -n "$ENV_FILE" ]; then
    # Since we cd'd, if env file was relative, we need to be careful. 
    # But checking if we resolved it? 
    # Actually we resolved CONTEXT_DIR, but ENV_FILE might be relative to original PWD.
    # To be safe, we should have resolved ENV_FILE to absolute path before cd.
    
    # Let's handle loading BEFORE cd, or resolve ENV_FILE too.
    # Simpler: just load valid file.
    if [[ "$ENV_FILE" = /* ]]; then
        load_env_vars "$ENV_FILE"
    else
        # It was relative to original pwd.
        # But we determined CONTEXT_DIR from it, so it's likely just basename in current dir?
        # Actually, if we cd'd to dirname(ENV_FILE), then ENV_FILE accessible as basename(ENV_FILE).
        load_env_vars "$(basename "$ENV_FILE")"
    fi
else
    # Fallback to local .env in context dir
    if [ -f ".env" ]; then
        echo "No specific .env file passed, using default .env"
        load_env_vars ".env"
    fi
fi

# Validate common requirements if necessary, or specific per mode.

case $MODE in
    test)
        # Check if FUNCTION_NAME is missing or is just a directory (like ".")
        if [ -z "$FUNCTION_NAME" ] || [ -d "$FUNCTION_NAME" ]; then
            SEARCH_DIR="${FUNCTION_NAME:-.}"
            DOCKERFILE="$SEARCH_DIR/Dockerfile"
            
            if [ -f "$DOCKERFILE" ]; then
                echo "Attempting to extract function name from $DOCKERFILE..."
                # Try to find --target=NAME
                EXTRACTED_NAME=$(grep -oE '\-\-target=[^ ]+' "$DOCKERFILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
                
                # If not found, try FUNCTION_TARGET=NAME
                if [ -z "$EXTRACTED_NAME" ]; then
                    EXTRACTED_NAME=$(grep "FUNCTION_TARGET" "$DOCKERFILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
                fi
                
                if [ -n "$EXTRACTED_NAME" ]; then
                    FUNCTION_NAME="$EXTRACTED_NAME"
                    echo "Found function name: $FUNCTION_NAME"
                else
                     echo "Error: Could not extract function name from Dockerfile."
                fi
            fi
        fi

        if [ -z "$FUNCTION_NAME" ] || [ -d "$FUNCTION_NAME" ]; then
             echo "Missing FUNCTION_NAME and Dockerfile. Please, create the Dockerfile or passed the FUNCTION_NAME to test"
             exit 1
        fi

        echo "--- Running Local Test ---"
        echo "Function: $FUNCTION_NAME"

        if [ "$USE_DOCKER" = true ]; then
             echo "--- Running with Docker ---"
             docker build -t "$FUNCTION_NAME" .
             
             DOCKER_ENV_ARGS=""
             # If we loaded env vars, we might want to pass them?
             # Or pass the env file.
             # If we resolved ENV_FILE, pass that.
             if [ -n "$ENV_FILE" ]; then
                 if [[ "$ENV_FILE" = /* ]]; then
                    DOCKER_ENV_ARGS="--env-file $ENV_FILE"
                 else
                    DOCKER_ENV_ARGS="--env-file $(pwd)/$(basename "$ENV_FILE")"
                 fi
             elif [ -f ".env" ]; then
                 DOCKER_ENV_ARGS="--env-file .env"
             fi
             
             echo "Starting container..."
             docker run -p 8080:8080 $DOCKER_ENV_ARGS "$FUNCTION_NAME"
        else
            echo "--- Running with Functions Framework ---"
            # functions-framework needs to be running in the dir with source
            functions-framework --target="$FUNCTION_NAME" --port=8080
        fi
        ;;

    deploy)
        # Ensure mandatory variables are present
        for key in "${REQUIRED_KEYS[@]}"; do
            if [ -z "${!key}" ]; then
                echo "Error: $key is not set. Please check your .env file."
                exit 1
            fi
        done

        echo "--- Deploying to Cloud Run ---"
        echo "Service: $SERVICE_NAME"
        echo "Project: $PROJECT_ID"
        
        # Helper to read env file for secrets
        SECRET_ARG=""
        ENV_FILE_NAME=""
        if [ -n "$ENV_FILE" ]; then
            ENV_FILE_NAME="$ENV_FILE"
        elif [ -f ".env" ]; then
            ENV_FILE_NAME=".env"
        fi
        
        if [ -n "$ENV_FILE_NAME" ]; then
             echo "--- Creating Secrets from $(basename "$ENV_FILE_NAME") ---"
             SECRETS_LIST=()
             
             # Read .env file line by line
             while IFS='=' read -r key value; do
                if [[ $key =~ ^#.* ]] || [[ -z $key ]]; then
                    continue
                fi
                value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
                MAPPING=$(handle_secret_value "$key" "$value" "$PROJECT_ID")
                if [ -n "$MAPPING" ]; then
                    SECRETS_LIST+=("$MAPPING")
                fi
             done < "$ENV_FILE_NAME"
             
             SECRET_ARG=$(IFS=,; echo "${SECRETS_LIST[*]}")
        fi

        # Submit build
        gcloud builds submit . --tag "gcr.io/$PROJECT_ID/$IMAGE_NAME" --project "$PROJECT_ID"
        
        # Deploy
        CMD="gcloud run deploy $SERVICE_NAME \
            --image gcr.io/$PROJECT_ID/$IMAGE_NAME \
            --region $REGION \
            --project $PROJECT_ID \
            --allow-unauthenticated"
            
        if [ -n "$SECRET_ARG" ]; then
            CMD="$CMD --set-secrets=$SECRET_ARG"
        fi
        
        eval "$CMD"
        ;;
        
    *)
        echo "Usage: $0 [--test FUNCTION_NAME] [--deploy] [--docker=True] [file.env]"
        exit 1
        ;;
esac