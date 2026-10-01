namespace ParkingManagement.Models
{
    public class UserManagementResult
    {
        public int StatusCode { get; set; }
        public string Message { get; set; } = "";
        public int? UserId { get; set; }
    }
}
