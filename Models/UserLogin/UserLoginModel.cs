using System.Text.Json.Serialization;

namespace ParkingManagement.Models
{
    public class UserLoginModel
    {
		public int UserID { get; set; }
		public string FirstName { get; set; } = "";
		public string LastName { get; set; } = "";
		public string Username { get; set; } = "";
		public string UserRole { get; set; } = "";
		public bool ActiveStatus { get; set; }

		[JsonIgnore]
		public string PasswordHash { get; set; } = "";
	}
}
