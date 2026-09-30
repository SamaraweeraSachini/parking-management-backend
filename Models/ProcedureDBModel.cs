using System.Data;

namespace ParkingManagement.Models
{
    public class ProcedureDBModel
    {
        public string ResultStatusCode { get; set; }
        public string Result { get; set; }
        public string ExceptionMessage { get; set; }
        public DataTable ResultDataTable { get; set; }
        public DataSet ResultDataSet { get; set; }
    }
}
