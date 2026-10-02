using System.ComponentModel.DataAnnotations;

namespace ParkingManagement.Models
{
    public class DailyEntryRequestAPI
    {
        [Required]
        [StringLength(30)]
        [RegularExpression(@"^[A-Za-z0-9 -]+$",
            ErrorMessage = "Vehicle number can contain letters, numbers, spaces and hyphens.")]
        public string VehicleNumber { get; set; } = "";

        [Range(1, int.MaxValue)]
        public int VehicleTypeID { get; set; }

        [Required]
        [RegularExpression("^DAILY$",
            ErrorMessage = "This endpoint accepts DAILY parking only.")]
        public string ParkingType { get; set; } = "";

        [Range(1, int.MaxValue)]
        public int? SpaceID { get; set; }

        [StringLength(200)]
        public string CustomerName { get; set; } = "";

        [StringLength(10)]
        public string MobileNumber { get; set; } = "";
    }
}