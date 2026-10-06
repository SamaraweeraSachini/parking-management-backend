using System.ComponentModel.DataAnnotations;

namespace ParkingManagement.Models
{
    public class MonthlyEntryRequestAPI
    {
        [Required]
        [StringLength(30)]
        [RegularExpression(
            @"^[A-Za-z0-9 -]+$",
            ErrorMessage = "Vehicle number can contain letters, numbers, spaces and hyphens.")]
        public string VehicleNumber { get; set; } = "";

        [Range(1, int.MaxValue)]
        public int VehicleTypeID { get; set; }

        [Required]
        [RegularExpression(
            "^MONTHLY$",
            ErrorMessage = "This endpoint accepts MONTHLY parking only.")]
        public string ParkingType { get; set; } = "";

        [Range(1, int.MaxValue)]
        public int? SpaceID { get; set; }
    }
}