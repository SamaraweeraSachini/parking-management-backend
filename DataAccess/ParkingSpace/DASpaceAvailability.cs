using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.DataAccess
{
    public class DASpaceAvailability : ISpaceAvailability
    {
        public List<SpaceAvailabilityModel> GetSpaces()
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(
                "dbo.PARKING_SP_Vehicle_Space",
                connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = 1;

            using var reader = command.ExecuteReader();

            var spaces = new List<SpaceAvailabilityModel>();

            while (reader.Read())
            {
                spaces.Add(new SpaceAvailabilityModel
                {
                    SpaceId = Convert.ToInt32(reader["SpaceID"]),
                    VehicleTypeId = Convert.ToInt32(reader["VehicleTypeID"]),
                    VehicleTypeName = reader["VehicleTypeName"].ToString(),
                    SpaceCode = reader["SpaceCode"].ToString(),
                    SpaceName = reader.IsDBNull(
                        reader.GetOrdinal("SpaceName"))
                            ? ""
                            : reader["SpaceName"].ToString(),
                    SpaceStatus = reader["SpaceStatus"]
                        .ToString()
                        .Trim()
                        .ToUpperInvariant()
                });
            }

            return spaces;
        }
    }
}