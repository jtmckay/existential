#!/bin/bash

# RabbitMQ Certificate Generation Script
# This script generates SSL certificates for RabbitMQ following the specified steps

# Function to generate RabbitMQ certificates
generate_rabbitmq_certs() {
    local rabbitmq_dir="$1"
    
    if [ -z "$rabbitmq_dir" ]; then
        echo "❌ Error: RabbitMQ directory path not provided"
        return 1
    fi
    
    if [ ! -d "$rabbitmq_dir" ]; then
        echo "❌ Error: RabbitMQ directory not found: $rabbitmq_dir"
        return 1
    fi
    
    local ssl_dir="$rabbitmq_dir/ssl"
    local config_file="$rabbitmq_dir/openssl-san.cnf"
    
    echo "🔐 Generating RabbitMQ SSL certificates..."
    echo "=========================================="
    echo "Directory: $rabbitmq_dir"
    
    # Check if openssl-san.cnf exists
    if [ ! -f "$config_file" ]; then
        echo "❌ Error: openssl-san.cnf not found at $config_file"
        echo "Please ensure the configuration file exists before generating certificates."
        return 1
    fi
    
    # Create ssl directory if it doesn't exist
    if [ ! -d "$ssl_dir" ]; then
        echo "📁 Creating SSL directory: $ssl_dir"
        mkdir -p "$ssl_dir"
    fi
    
    # Check if certificates already exist
    if [ -f "$ssl_dir/server_cert.pem" ] && [ -f "$ssl_dir/server_key.pem" ] && [ -f "$ssl_dir/ca.pem" ] && [ -f "$ssl_dir/client_cert.pem" ] && [ -f "$ssl_dir/client_key.pem" ] && [ -f "$ssl_dir/client.pem" ]; then
        echo "ℹ️  SSL certificates already exist. Skipping generation."
        echo "   To regenerate, delete the existing certificates first."
        return 0
    fi
    
    echo "🔑 Step 1: Generating server certificate and key..."
    
    # Generate server certificate and key
    if ! openssl req -x509 -nodes -newkey rsa:4096 \
        -days 3650 \
        -keyout "$ssl_dir/server_key.pem" \
        -out "$ssl_dir/server_cert.pem" \
        -config "$config_file" \
        -extensions v3_req 2>/dev/null; then
        echo "❌ Error: Failed to generate server certificate"
        return 1
    fi
    
    echo "🔗 Step 2: Combining server certificate and key into ca.pem..."
    
    # Combine server cert and key into ca.pem
    if ! cat "$ssl_dir/server_key.pem" "$ssl_dir/server_cert.pem" > "$ssl_dir/ca.pem"; then
        echo "❌ Error: Failed to create ca.pem"
        return 1
    fi
    
    echo "🔑 Step 3: Generating client certificate..."
    
    # Generate client private key
    if ! openssl genrsa -out "$ssl_dir/client_key.pem" 2048 2>/dev/null; then
        echo "❌ Error: Failed to generate client private key"
        return 1
    fi
    
    # Generate client certificate request
    if ! openssl req -new -key "$ssl_dir/client_key.pem" -out "$ssl_dir/client_req.pem" -subj "/CN=rabbitmq-client" 2>/dev/null; then
        echo "❌ Error: Failed to generate client certificate request"
        return 1
    fi
    
    # Generate client certificate signed by server certificate
    if ! openssl x509 -req -in "$ssl_dir/client_req.pem" -CA "$ssl_dir/server_cert.pem" \
        -CAkey "$ssl_dir/server_key.pem" -CAcreateserial -out "$ssl_dir/client_cert.pem" 2>/dev/null; then
        echo "❌ Error: Failed to generate client certificate"
        return 1
    fi
    
    # Combine client certificate and key
    if ! cat "$ssl_dir/client_cert.pem" "$ssl_dir/client_key.pem" > "$ssl_dir/client.pem"; then
        echo "❌ Error: Failed to create client.pem"
        return 1
    fi
    
    echo "🔒 Step 4: Setting proper permissions..."
    
    # Set proper permissions
    chmod 644 "$ssl_dir"/*.pem
    
    # Clean up temporary files
    rm -f "$ssl_dir/client_req.pem" "$ssl_dir/server_cert.srl"
    
    echo "✅ RabbitMQ SSL certificates generated successfully!"
    echo "   Files created in $ssl_dir:"
    echo "   • server_cert.pem (Server certificate)"
    echo "   • server_key.pem (Server private key)"
    echo "   • ca.pem (Combined server cert and key)"
    echo "   • client_cert.pem (Client certificate)"
    echo "   • client_key.pem (Client private key)"
    echo "   • client.pem (Combined client cert and key)"
    echo ""
    
    return 0
}

# Function to check if RabbitMQ service exists and generate certificates if needed
check_and_generate_rabbitmq_certs() {
    local base_dir="${1:-.}"
    local rabbitmq_service_dir="$base_dir/services/rabbitMQ"
    
    # Check if RabbitMQ service directory exists
    if [ -d "$rabbitmq_service_dir" ]; then
        echo "🐰 Found RabbitMQ service directory"
        generate_rabbitmq_certs "$rabbitmq_service_dir"
        return $?
    else
        echo "ℹ️  RabbitMQ service directory not found, skipping certificate generation"
        return 0
    fi
}

# If script is run directly (not sourced), execute the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_and_generate_rabbitmq_certs "$@"
fi
