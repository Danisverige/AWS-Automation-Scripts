#!/bin/bash

# Load variables from resources.env
if [ ! -f resources.env ]; then
  echo "❌ resources.env not found. Nothing to clean up."
  exit 1
fi

source resources.env

echo "🧹 Starting cleanup..."
echo "INSTANCE_ID: $INSTANCE_ID"
echo "SECURITY_GROUP_ID: $SECURITY_GROUP_ID"
echo "KEY_NAME: $KEY_NAME"

# Terminate EC2 instance
if [ -n "$INSTANCE_ID" ]; then
  echo "⏳ Terminating EC2 instance: $INSTANCE_ID"
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --output text
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
  echo "✅ Instance terminated."
else
  echo "⚠️  No instance ID found."
fi

# Delete security group
if [ -n "$SECURITY_GROUP_ID" ]; then
  echo "🗑️  Deleting security group: $SECURITY_GROUP_ID"
  aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID"
  echo "✅ Security group deleted."
else
  echo "⚠️  No security group ID found."
fi

# Delete key pair in AWS
if [ -n "$KEY_NAME" ]; then
  echo "🗝️  Deleting AWS key pair: $KEY_NAME"
  aws ec2 delete-key-pair --key-name "$KEY_NAME"
  echo "✅ Key pair deleted from AWS."

  # Delete local SSH keys
  echo "🧻 Deleting local SSH keys..."
  rm -f "$HOME/.ssh/id_rsa_${KEY_NAME}" "$HOME/.ssh/id_rsa_${KEY_NAME}.pub"
  echo "✅ Local SSH keys deleted."
else
  echo "⚠️  No key pair name found."
fi

# Optional: Remove env file
read -p "🧼 Delete resources.env file? (y/n): " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  rm -f resources.env
  echo "🧽 resources.env removed."
else
  echo "📦 Keeping resources.env."
fi

echo "✅ Cleanup complete!"
