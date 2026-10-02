namespace ParkingManagement.Models
{
    public class SpaceAvailabilityModel
    {
        public int SpaceId { get; set; }
        public int VehicleTypeId { get; set; }
        public string VehicleTypeName { get; set; } = "";
        public string SpaceCode { get; set; } = "";
        public string SpaceName { get; set; } = "";
        public string SpaceStatus { get; set; } = "";
    }
}
