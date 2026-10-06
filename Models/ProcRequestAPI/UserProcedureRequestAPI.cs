namespace ParkingManagement.Models
{
    public class UserProcedureRequestAPI : RequestAPI
    {
        public int? UserID { get; set; }
        public string FirstName { get; set; }
        public string LastName { get; set; }
        public string Username { get; set; }
        public string PasswordHash { get; set; }
        public string UserRole { get; set; }
        public int? PerformedByUserID { get; set; }
    }
}
