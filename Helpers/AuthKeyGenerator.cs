namespace ParkingManagement.Helpers
{
    public static class AuthKeyGenerator
    {
        public static string GenerateAuthKey(string userId, string userType,string username, string clientCode)
        {
            string raw = (userId ?? "") + "`" + (userType ?? "") + "`" + (username ?? "") + "`" + (clientCode ?? "");

            return EncryptionHelper.EncryptStringAES(raw);
        }
    }
}
