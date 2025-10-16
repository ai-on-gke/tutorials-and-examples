import time
import os

import jwt

client_id = os.environ.get("GH_CLIENT_ID")
signing_key = os.environ.get("GH_PEM")

payload = {
    # Issued at time
    'iat': int(time.time()),
    # JWT expiration time (10 minutes maximum)
    'exp': int(time.time()) + 300,

    # GitHub App's client ID
    'iss': client_id

}

# Create JWT
encoded_jwt = jwt.encode(payload, signing_key, algorithm='RS256')

print(encoded_jwt)
