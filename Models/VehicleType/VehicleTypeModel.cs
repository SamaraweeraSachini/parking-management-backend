using System.ComponentModel.DataAnnotations;

namespace ParkingManagement.Models.VehicleType
{
    public class VehicleTypeModel
    {
        public int VehicleTypeID { get; set; }

        [Required(ErrorMessage = "Vehicle type name is required.")]
        [StringLength(100)]
        public string TypeName { get; set; } = string.Empty;

        [StringLength(500)]
        public string Description { get; set; }

        public bool ActiveStatus { get; set; }

        public DateTime CreatedAt { get; set; }
        public int? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int? UpdatedBy { get; set; }
    }
}
