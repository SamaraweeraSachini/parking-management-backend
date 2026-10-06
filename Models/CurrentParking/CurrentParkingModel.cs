namespace ParkingManagement.Models
{
    public class CurrentParkingModel
    {
        public int TicketID { get; set; }
        public string TicketNumber { get; set; } = "";
        public string VehicleNumber { get; set; } = "";
        public string VehicleType { get; set; } = "";
        public string ParkingType { get; set; } = "";
        public int SpaceID { get; set; }
        public string SpaceCode { get; set; } = "";
        public DateTime EntryDateTime { get; set; }
        public string TicketStatus { get; set; } = "";
    }
}
