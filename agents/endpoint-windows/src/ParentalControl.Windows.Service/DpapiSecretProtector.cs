using System.Security.Cryptography;
using System.Text;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.Service;

internal sealed class DpapiSecretProtector : ISecretProtector
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("ParentalControl.Windows.Endpoint.v1");

    public byte[] Protect(ReadOnlySpan<byte> cleartext) => ProtectedData.Protect(
        cleartext.ToArray(), Entropy, DataProtectionScope.LocalMachine);

    public byte[] Unprotect(ReadOnlySpan<byte> ciphertext) => ProtectedData.Unprotect(
        ciphertext.ToArray(), Entropy, DataProtectionScope.LocalMachine);
}
