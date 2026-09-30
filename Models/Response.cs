namespace ParkingManagement.Models
{
    public class Response
    {
        public int StatusCode { get; set; } = 404;
        public string Result { get; set; }
        public object ResultSet { get; set; }
        public object ExceptionMessage { get; set; }
    }
}
