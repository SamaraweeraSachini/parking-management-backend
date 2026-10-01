using System.ComponentModel.DataAnnotations;

namespace ParkingManagement.Models
{
    public class UpdateUserRequestAPI
    {
        [Required]
        [StringLength(100)]
        public string FirstName { get; set; } = "";

        [Required]
        [StringLength(100)]
        public string LastName { get; set; } = "";

        [Required]
        [StringLength(100)]
        public string Username { get; set; } = "";

        [Required]
        [RegularExpression("^(A|O)$",
            ErrorMessage = "Role must be A for Admin or O for Operator.")]
        public string UserRole { get; set; } = "";
    }

    public class CreateUserRequestAPI : UpdateUserRequestAPI
    {
        [Required]
        [MinLength(12)]
        public string Password { get; set; } = "";
    
    }
}
