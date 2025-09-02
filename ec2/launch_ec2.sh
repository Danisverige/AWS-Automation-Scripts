#!/bin/bash

# Prompt for input
read -p "What do you want to name your key pair? " MY_KEYNAME
read -p "What do you want to name your security group? " MY_SG_NAME
read -p "What do you want to name your EC2 instance? " MY_INSTANCE_NAME

# Get current user
MY_USER=$(aws sts get-caller-identity --query 'Arn' --output text | awk -F '/' '{print $2}')

# Generate SSH key pair with passphrase prompt
MY_SSH="$HOME/.ssh/id_rsa_${MY_KEYNAME}"
echo "Creating SSH key pair at $MY_SSH..."
ssh-keygen -t rsa -f "$MY_SSH"  # prompts for passphrase
echo "SSH key generated."

# Import public key to AWS
aws ec2 import-key-pair \
  --key-name "$MY_KEYNAME" \
  --public-key-material fileb://"${MY_SSH}.pub"

# Get your public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" --output text)

# Create security group
MY_SG=$(aws ec2 create-security-group \
  --group-name "$MY_SG_NAME" \
  --description "SSH & HTTP access for $MY_USER" \
  --vpc-id "$DEFAULT_VPC" \
  --output json | jq -r .GroupId)

# Authorize SSH and HTTP ingress from your IP
aws ec2 authorize-security-group-ingress \
  --group-id "$MY_SG" \
  --protocol tcp --port 22 \
  --cidr "$MY_IP/32" --no-cli-pager

aws ec2 authorize-security-group-ingress \
  --group-id "$MY_SG" \
  --protocol tcp --port 80 \
  --cidr "$MY_IP/32" --no-cli-pager

# Get first subnet in default VPC
MY_SUBNET=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
  --query "Subnets[0].SubnetId" \
  --output text)

echo "Subnet ID: $MY_SUBNET"

# Launch EC2 instance
AMI_ID="ami-0c4fc5dcabc9df21d"  # Amazon Linux 2 (update as needed)
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "t3.micro" \
  --key-name "$MY_KEYNAME" \
  --security-group-ids "$MY_SG" \
  --subnet-id "$MY_SUBNET" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$MY_INSTANCE_NAME}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Instance ID: $INSTANCE_ID"

# Wait for instance to be running
echo "Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "Instance is running."

# Get public DNS of the instance
MY_EC2=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text)

echo "Instance Public DNS: $MY_EC2"

# Save values for cleanup
cat > resources.env <<EOF
INSTANCE_ID=$INSTANCE_ID
SECURITY_GROUP_ID=$MY_SG
KEY_NAME=$MY_KEYNAME
EOF

# Start ssh-agent and add key
eval "$(ssh-agent -s)"
ssh-add "$MY_SSH"

# Smart wait for SSH to be ready
echo "⏳ Waiting for SSH to become available at $MY_EC2..."

SSH_READY=false
for i in {1..12}; do  # try up to 12 times (~1 minute)
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$MY_SSH" ec2-user@"$MY_EC2" "echo SSH is ready" >/dev/null 2>&1; then
    SSH_READY=true
    echo "✅ SSH is ready!"
    break
  else
    echo "⏱️  Attempt $i: SSH not ready yet..."
    sleep 5
  fi
done

if [ "$SSH_READY" = false ]; then
  echo "❌ SSH connection failed after multiple attempts."
  exit 1
fi

# Connect to EC2 instance
ssh ec2-user@"$MY_EC2"
