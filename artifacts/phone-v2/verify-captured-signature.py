#!/usr/bin/env python3
"""Public diagnostic only; this arithmetic is not production cryptography."""
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

import cryptography
from cryptography.hazmat.backends.openssl.backend import backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

directory = Path(__file__).resolve().parent
fixture = json.loads((directory / 'apple-fixture-verification-reproducer.json').read_text())
message = bytes.fromhex(fixture['messageHex'])
signature = bytes.fromhex(fixture['signatureDERHex'])
public = bytes.fromhex(fixture['publicKeyHex'])
key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), public)

# Parse this short-form P-256 DER signature independently of cryptography.
assert signature[0] == 0x30 and signature[1] == len(signature) - 2
offset = 2
scalars = []
for _ in range(2):
    assert signature[offset] == 2
    length = signature[offset + 1]
    integer = signature[offset + 2:offset + 2 + length]
    assert len(integer) == length and 1 <= length <= 33
    assert integer[0] < 128
    assert length == 1 or integer[0] != 0 or integer[1] >= 128
    scalars.append(int.from_bytes(integer, 'big'))
    offset += 2 + length
assert offset == len(signature)
r, s = scalars

p = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
n = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
a = p - 3
b = 0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b
generator = (
    0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,
    0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5,
)
point = (int.from_bytes(public[1:33], 'big'), int.from_bytes(public[33:], 'big'))


def add(left, right):
    if left is None:
        return right
    if right is None:
        return left
    x, y = left
    u, v = right
    if x == u and (y + v) % p == 0:
        return None
    if left == right:
        slope = (3 * x * x + a) * pow(2 * y, -1, p) % p
    else:
        slope = (v - y) * pow(u - x, -1, p) % p
    result_x = (slope * slope - x - u) % p
    return result_x, (slope * (x - result_x) - y) % p


def multiply(scalar, value):
    result = None
    while scalar:
        if scalar & 1:
            result = add(result, value)
        value = add(value, value)
        scalar >>= 1
    return result


assert 0 < r < n and 0 < s < n
assert point[1] ** 2 % p == (point[0] ** 3 + a * point[0] + b) % p
assert multiply(n, generator) is None and multiply(9, generator) == point
digest = hashlib.sha256(message).digest()
assert digest.hex() == fixture['messageSHA256']
inverse = pow(s, -1, n)
calculated = add(multiply(int.from_bytes(digest, 'big') * inverse % n, generator),
                 multiply(r * inverse % n, point))
results = {'purePythonAffineECDSA': calculated is not None and calculated[0] % n == r}
try:
    key.verify(signature, message, ec.ECDSA(hashes.SHA256()))
    valid = True
except Exception:
    valid = False
results['pythonCryptography'] = {
    'version': cryptography.__version__, 'backend': backend.openssl_version_text(), 'valid': valid,
}
with tempfile.TemporaryDirectory() as temporary:
    path = Path(temporary)
    (path / 'public.pem').write_bytes(key.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    (path / 'message').write_bytes(message)
    (path / 'signature').write_bytes(signature)
    for executable in ['/usr/bin/openssl', '/opt/homebrew/opt/openssl@3/bin/openssl']:
        if not Path(executable).exists():
            results[executable] = {'available': False}
            continue
        version = subprocess.run([executable, 'version'], capture_output=True, text=True, check=True).stdout.strip()
        result = subprocess.run([executable, 'dgst', '-sha256', '-verify', str(path / 'public.pem'),
                                 '-signature', str(path / 'signature'), str(path / 'message')], capture_output=True, text=True)
        results[executable] = {'version': version, 'exitCode': result.returncode,
                               'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}
print(json.dumps(results, indent=2))
