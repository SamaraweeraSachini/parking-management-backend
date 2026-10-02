namespace ParkingManagement.Models
{
    public class EntryVehicleTypeModel
    {
        public int VehicleTypeID { get; set; }
        public string TypeName { get; set; } = "";
    }

    public class EntrySpaceModel
    {
        public int SpaceID { get; set; }
        public string SpaceCode { get; set; } = "";
        public string SpaceName { get; set; } = "";
    }

    public class DailyEntryResult
    {
        public int StatusCode { get; set; }
        public string Message { get; set; } = "";

        public int? TicketID { get; set; }
        public string TicketNumber { get; set; } = "";
        public string VehicleNumber { get; set; } = "";
        public int? SpaceID { get; set; }
        public DateTime? EntryDateTime { get; set; }
    }
}