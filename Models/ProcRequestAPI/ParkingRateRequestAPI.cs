using System.ComponentModel.DataAnnotations;

namespace ParkingManagement.Models
{
    public class ParkingRateRequestAPI
    {
        [Range(1, int.MaxValue, ErrorMessage = "Select a valid vehicle type.")]
        public int VehicleTypeID { get; set; }

        [Required]
        [StringLength(100)]
        public string RateName { get; set; } = "";

        [Required]
        [Range(typeof(decimal), "0", "9999999999.99", ErrorMessage = "Amount must be between 0 and 9999999999.99.")]
        public decimal? RateAmount { get; set; }

        [Required]
        [RegularExpression("^(HOURLY|DAILY)$", ErrorMessage = "Rate unit must be HOURLY or DAILY.")]
        public string RateUnit { get; set; } = "";

        public DateTimeOffset? EffectiveFrom { get; set; }
        public DateTimeOffset? EffectiveTo { get; set; }
    }
}