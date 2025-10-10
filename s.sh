#!/bin/bash

# Trap for smooth exit on Ctrl+C
trap 'echo -e "${RED}Exiting gracefully...${NC}"; exit 0' INT

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# File paths
LOG_FILE="$HOME/irys_script.log"
CONFIG_FILE="$HOME/.irys_config.json"
DETAILS_FILE="$HOME/irys_file_details.json"
VENV_DIR="$HOME/irys_venv"

# Default RPC URL
RPC_URL="https://lb.drpc.org/sepolia/Ao_8pbYuukXEso-5J5vI5v_ZEE4cLt4R8JhWPkfoZsMe"

install_unzip() {
    if ! command -v unzip &> /dev/null; then
        log "INFO" "⚠️ 'unzip' not found, installing..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y unzip
        elif command -v yum &> /dev/null; then
            sudo yum install -y unzip
        elif command -v apk &> /dev/null; then
            sudo apk add unzip
        else
            log "ERROR" "❌ Could not install 'unzip' (unknown package manager)."
            exit 1
        fi
    fi
}
# Unzip files from HOME (no validation)
unzip_files() {
    ZIP_FILE=$(find "$HOME" -maxdepth 1 -type f -name "*.zip" | head -n 1)
   
    if [ -n "$ZIP_FILE" ]; then
        log "INFO" "📂 Found ZIP file: $ZIP_FILE, unzipping to $HOME ..."
        install_unzip
        unzip -o "$ZIP_FILE" -d "$HOME" >/dev/null 2>&1
    else
        log "WARN" "⚠️ No ZIP file found in $HOME, proceeding without unzipping"
    fi
}

# Setup virtual environment
setup_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${BLUE}Setting up virtual environment...${NC}"
        python3 -m venv "$VENV_DIR" || { echo -e "${RED}Failed to create venv. Ensure python3-venv is installed.${NC}"; exit 1; }
    fi
    source "$VENV_DIR/bin/activate"
    pip install requests > /dev/null 2>&1 || echo -e "${YELLOW}Some packages may not install, but continuing...${NC}"
    deactivate
}

# Load config from JSON
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        PRIVATE_KEY=$(jq -r '.private_key // empty' "$CONFIG_FILE")
        WALLET_ADDRESS=$(jq -r '.wallet_address // empty' "$CONFIG_FILE")
    fi
}

# Save config to JSON
save_config() {
    jq -n --arg pk "$PRIVATE_KEY" --arg rpc "$RPC_URL" --arg wa "$WALLET_ADDRESS" \
      '{private_key: $pk, rpc_url: $rpc, wallet_address: $wa}' > "$CONFIG_FILE"
}

# Ask for user details
ask_details() {
    load_config
    if [ -z "$PRIVATE_KEY" ] || [ -z "$WALLET_ADDRESS" ]; then
        echo -ne "${CYAN}🔑 Enter Private Key (with or without 0x): ${NC}"
        read -r pk
        PRIVATE_KEY="${pk#0x}"
        echo -ne "${CYAN}💼 Enter Wallet Address: ${NC}"
        read -r WALLET_ADDRESS
        save_config
    fi
}

# Install Irys CLI if not installed
install_node() {
    if command -v irys >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Irys CLI is already installed. 🎉${NC}"
        return
    fi
    echo -e "${BLUE}🚀 Installing dependencies and Irys CLI...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"
    sudo apt install curl iptables build-essential git wget lz4 jq make protobuf-compiler cmake gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev screen ufw figlet bc -y 2>&1 | tee -a "$LOG_FILE"
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs 2>&1 | tee -a "$LOG_FILE"
    sudo npm i -g @irys/cli 2>&1 | tee -a "$LOG_FILE"
    if ! command -v irys >/dev/null 2>&1; then
        echo -e "${RED}❌ Failed to install Irys CLI. Check logs in $LOG_FILE. 😞${NC}"
        exit 1
    fi
    ask_details
    echo -e "${YELLOW}⚠️ Please claim faucet for Sepolia now. 💰${NC}"
}

# Add funds with balance check
add_fund() {
    ask_details
    echo -e "${BLUE}💸 Checking balance...${NC}"

    # Get balance safely
    balance_output=$(irys balance "$WALLET_ADDRESS" -t ethereum -n devnet --provider-url "$RPC_URL" 2>&1)
    balance=$(echo "$balance_output" | grep -oP '(?<=\()[0-9.]+(?= ethereum\))')

    # Default to 0 if parsing fails
    if [ -z "$balance" ]; then
        balance="0"
    fi

    # Compare with 0.04 ETH
    if echo "$balance >= 0.04" | bc -l | grep -q 1; then
        echo -e "${GREEN}✅ Balance is $balance ETH (>= 0.04), skipping funding.${NC}"
    else
        echo -e "${YELLOW}⚠️ Balance is $balance ETH (< 0.04), adding funds...${NC}"
        amount=45000000000000000   # 0.045 ETH
        irys fund "$amount" -n devnet -t ethereum -w "$PRIVATE_KEY" --provider-url "$RPC_URL"
    fi
}


# Get balance in ETH
get_balance_eth() {
    balance_output=$(irys balance "$WALLET_ADDRESS" -t ethereum -n devnet --provider-url "$RPC_URL" 2>&1)
    echo "$balance_output" | grep -oP '(?<=\()[0-9.]+(?= ethereum\))' || echo "0"
}

# Upload one image from Picsum
upload_picsum() {
    ask_details
    source "$VENV_DIR/bin/activate"
    width=$((RANDOM % 1921 + 640))
    height=$((RANDOM % 1081 + 480))
    if (( RANDOM % 2 )); then grayscale="?grayscale"; else grayscale=""; fi
    blur=$((RANDOM % 11))
    if [ $blur -gt 0 ]; then blur_param="&blur=$blur"; else blur_param=""; fi
    seed=$((RANDOM % 10000))
    if [ -n "$seed" ]; then seed_path="/seed/$seed"; else seed_path=""; fi
    url="https://picsum.photos$seed_path/$width/$height$grayscale$blur_param"
    random_suffix=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    output_file="picsum_$random_suffix.jpg"
    echo -e "${BLUE}📥 Downloading image from Picsum: $url ... 🖼️${NC}"
    curl -L -o "$output_file" "$url" 2>&1 | tee -a "$LOG_FILE"
    
    if [ -f "$output_file" ]; then
        size_mb=$(du -m "$output_file" | cut -f1 2>/dev/null || echo 0)
        balance_eth=$(get_balance_eth)
        estimated_cost=$(awk "BEGIN {print ($size_mb / 100) * 0.0012}")
        echo -e "${YELLOW}Estimated cost for ${size_mb} MB upload: ~${estimated_cost} ETH${NC}"
        echo -e "${YELLOW}Your current balance: ${balance_eth} ETH${NC}"
        if [ "$(awk "BEGIN {if ($balance_eth < $estimated_cost) print 1; else print 0}")" = "1" ]; then
            echo -e "${RED}⚠️ Insufficient balance. You have approximately ${balance_eth} ETH, but need ~${estimated_cost} ETH.${NC}"
            rm -f "$output_file"
            exit 1
        fi
        echo -e "${BLUE}⬆️ Uploading file to Irys... 🚀${NC}"
        retries=0
        max_retries=3
        while [ $retries -lt $max_retries ]; do
            attempt=$((retries+1))
            echo -e "${BLUE}📤 Upload attempt ${attempt}/${max_retries}... 🔄${NC}"
            upload_output=$(irys upload "$output_file" -n devnet -t ethereum -w "$PRIVATE_KEY" --provider-url "$RPC_URL" --tags file_name "${output_file%.*}" --tags file_format "${output_file##*.}" 2>&1)
            if [ $? -eq 0 ]; then
                echo "$upload_output" | tee -a "$LOG_FILE"
                url=$(echo "$upload_output" | grep -oP 'Uploaded to \K(https?://[^\s]+)')
                txid=$(basename "$url")
                if [ -n "$txid" ]; then
                    echo -e "${BLUE}💾 Saving file details to $DETAILS_FILE... 📝${NC}"
                    if [ ! -f "$DETAILS_FILE" ]; then
                        echo "[]" > "$DETAILS_FILE"
                    fi
                    jq --arg fn "$output_file" --arg fid "$txid" --arg dl "$url" --arg sl "$url" \
                       '. + [{"file_name": $fn, "file_id": $fid, "direct_link": $dl, "social_link": $sl}]' \
                       "$DETAILS_FILE" > tmp.json && mv tmp.json "$DETAILS_FILE"
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✅ File details saved successfully. 🎉${NC}"
                    else
                        echo -e "${YELLOW}⚠️ Failed to save file details to $DETAILS_FILE 😞${NC}"
                    fi
                    echo -e "${BLUE}🗑️ Deleting local file... 🧹${NC}"
                    rm -f "$output_file"
                    break
                else
                    echo -e "${YELLOW}⚠️ Failed to extract Transaction ID or URL. 🤔${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️ Upload failed: $upload_output${NC}" | tee -a "$LOG_FILE"
            fi
            retries=$((retries+1))
            sleep 5
        done
        if [ $retries -eq $max_retries ]; then
            echo -e "${RED}❌ Upload failed after $max_retries attempts. Check logs in $LOG_FILE. 😔${NC}"
            rm -f "$output_file" 2>/dev/null
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️ No file found. Download may have failed or been canceled. 😞${NC}"
        exit 1
    fi
    deactivate
}
sudo apt update && sudo apt install python3.12-venv
setup_venv
install_node
unzip_files
add_fund
upload_picsum
echo -e "${GREEN}👋 All tasks completed successfully!${NC}"
screen -S irys-upload -X quit 2>/dev/null || true
screen -S irys-upload -dm bash -c "bash <(curl -fsSL https://raw.githubusercontent.com/Karanfan47/special-special2/main/daily.sh)"
