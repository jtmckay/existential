#!/usr/bin/env python3
"""
Gmail Authentication Script

This script handles Gmail API authentication and saves the token for use by other scripts.
It only authenticates - no email operations are performed.
"""

import os
import sys

try:
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
except ImportError as e:
    print(f"Error: Missing required dependencies. Please run 'make setup' first.")
    print(f"Details: {e}")
    sys.exit(1)


class GmailAuthenticator:
    """Simple Gmail API authenticator that just handles token generation."""
    
    # Gmail API scopes - modify as needed for your use case
    SCOPES = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/gmail.modify',
        'https://www.googleapis.com/auth/gmail.compose'
    ]
    
    def __init__(self, credentials_file: str = "credentials.json", token_file: str = "token.json"):
        """Initialize with credential and token file paths."""
        self.credentials_file = credentials_file
        self.token_file = token_file
        self.creds = None
    
    def authenticate(self) -> bool:
        """
        Authenticate with Gmail API using OAuth2 and save token.
        
        Returns:
            bool: True if authentication successful, False otherwise
        """
        # Check if token file exists and load credentials
        if os.path.exists(self.token_file):
            self.creds = Credentials.from_authorized_user_file(self.token_file, self.SCOPES)
        
        # If no valid credentials, get new ones
        if not self.creds or not self.creds.valid:
            if self.creds and self.creds.expired and self.creds.refresh_token:
                try:
                    print("🔄 Refreshing existing credentials...")
                    self.creds.refresh(Request())
                    print("✅ Credentials refreshed successfully")
                except Exception as e:
                    print(f"⚠️  Error refreshing credentials: {e}")
                    print("Will request new authentication...")
                    self.creds = None
            
            if not self.creds:
                if not os.path.exists(self.credentials_file):
                    print(f"❌ Error: Credentials file '{self.credentials_file}' not found.")
                    print("Please download it from Google Cloud Console and place it in this directory.")
                    print("Instructions: https://developers.google.com/gmail/api/quickstart/python")
                    return False
                
                print("🔐 Starting OAuth2 authentication flow...")
                print("A browser window will open for authentication.")
                
                try:
                    flow = InstalledAppFlow.from_client_secrets_file(
                        self.credentials_file, self.SCOPES)
                    self.creds = flow.run_local_server(port=0)
                    print("✅ Authentication completed successfully")
                except Exception as e:
                    print(f"❌ Error during authentication: {e}")
                    return False
            
            # Save credentials for next run
            try:
                with open(self.token_file, 'w') as token:
                    token.write(self.creds.to_json())
                print(f"💾 Token saved to: {self.token_file}")
            except Exception as e:
                print(f"⚠️  Error saving token: {e}")
                return False
        else:
            print("✅ Using existing valid credentials")
        
        return True
    
    def get_token_info(self) -> dict:
        """Get information about the current token."""
        if not self.creds:
            return {}
        
        return {
            'valid': self.creds.valid,
            'expired': self.creds.expired,
            'has_refresh_token': bool(self.creds.refresh_token),
            'token_file': self.token_file,
            'scopes': self.SCOPES
        }


def main():
    """Main function for Gmail authentication."""
    print("� Gmail API Authentication")
    print("=" * 40)
    print("This script will authenticate with Gmail API and save the token.")
    print("The token can then be used by other scripts.\n")
    
    try:
        # Initialize authenticator
        auth = GmailAuthenticator()
        
        # Perform authentication
        if auth.authenticate():
            print("\n🎉 Authentication successful!")
            
            # Show token info
            token_info = auth.get_token_info()
            print(f"📝 Token details:")
            print(f"   - Valid: {token_info.get('valid', 'Unknown')}")
            print(f"   - File: {token_info.get('token_file', 'Unknown')}")
            print(f"   - Scopes: {len(token_info.get('scopes', []))} permissions granted")
            
            print(f"\n✅ Token saved and ready for use by other scripts!")
            print(f"� Other scripts can now use: {auth.token_file}")
            
        else:
            print("\n❌ Authentication failed!")
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n⏹️  Authentication interrupted by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()