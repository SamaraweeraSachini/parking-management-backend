using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.DataAccess
{
    public class DACurrentParking : ICurrentParking
    {
        public List<CurrentParkingModel> GetCurrentParking(string searchTerm)
        {
            var result = new List<CurrentParkingModel>();

            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand("dbo.PARKING_SP_Ticket_Search", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            bool searching = !string.IsNullOrWhiteSpace(searchTerm);

            command.Parameters.Add("@ActionType", SqlDbType.Int).Value = searching ? 2 : 1;

            command.Parameters.Add("@SearchTerm", SqlDbType.NVarChar, 200).Value = searching ? (object)searchTerm.Trim() : DBNull.Value;

            using var reader = command.ExecuteReader();

            while (reader.Read())
            {
                result.Add(new CurrentParkingModel
                {
                    TicketID = Convert.ToInt32(reader["TicketID"]),
                    TicketNumber = reader["TicketNumber"].ToString() ?? "",
                    VehicleNumber = reader["VehicleNumber"].ToString() ?? "",
                    VehicleType = reader["VehicleType"].ToString() ?? "",
                    ParkingType = reader["ParkingType"].ToString() ?? "",
                    SpaceID = Convert.ToInt32(reader["SpaceID"]),
                    SpaceCode = reader["SpaceCode"].ToString() ?? "",
                    TicketStatus = reader["TicketStatus"].ToString() ?? "",
                    EntryDateTime = DateTime.SpecifyKind(Convert.ToDateTime(reader["EntryDateTime"]), DateTimeKind.Utc)
                });
            }

            return result;
        }
    }
}