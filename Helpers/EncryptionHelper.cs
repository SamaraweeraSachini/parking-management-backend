using System.Security.Cryptography;
using System.Text;

namespace ParkingManagement.Helpers
{
    public static class EncryptionHelper
    {
        private const string Key = "12345678901234567890123456789012";

        public static string EncryptStringAES(string plainText)
        {
            using (Aes aes = Aes.Create())
            {
                aes.Key = Encoding.UTF8.GetBytes(Key);

                aes.GenerateIV();

                using (MemoryStream memoryStream = new MemoryStream())
                {
                    memoryStream.Write(aes.IV, 0, aes.IV.Length);

                    using (CryptoStream cryptoStream = new CryptoStream( memoryStream, aes.CreateEncryptor(),  CryptoStreamMode.Write))
                    {
                        using (StreamWriter writer = new StreamWriter(cryptoStream))
                        {
                            writer.Write(plainText);
                        }
                    }

                    return Convert.ToBase64String(memoryStream.ToArray());
                }
            }
        }

        public static string DecryptStringAES(string cipherText)
        {
            byte[] buffer =  Convert.FromBase64String(cipherText);

            using (Aes aes = Aes.Create())
            {
                aes.Key = Encoding.UTF8.GetBytes(Key);

                using (MemoryStream memoryStream = new MemoryStream(buffer))
                {
                    byte[] iv = new byte[16];

                    int bytesRead = memoryStream.Read( iv, 0, 16);

                    if (bytesRead != 16)
                    {
                        throw new CryptographicException("Invalid AuthKey.");
                    }

                    aes.IV = iv;

                    using (CryptoStream cryptoStream = new CryptoStream( memoryStream,  aes.CreateDecryptor(), CryptoStreamMode.Read))
                    {
                        using (StreamReader reader = new StreamReader(cryptoStream))
                        {
                            return reader.ReadToEnd();
                        }
                    }
                }
            }
        }
    }
}