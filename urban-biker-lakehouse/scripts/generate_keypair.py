import os
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

key_dir = os.path.join(os.path.dirname(__file__), "..", ".certs")
os.makedirs(key_dir, exist_ok=True)

private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
    backend=default_backend()
)
private_path = os.path.join(key_dir, "rsa_key.p8")
public_path = os.path.join(key_dir, "rsa_key.pub")

with open(private_path, "wb") as f:
    f.write(private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ))
with open(public_path, "wb") as f:
    f.write(private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ))

print(f"Keys generated at: {key_dir}")
