using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.DataAccess
{
    public class DAVehicleEntry : IVehicleEntry
    {
        public List<EntryVehicleTypeModel> GetActiveVehicleTypes()
        {
            var result = new List<EntryVehicleTypeModel>();

            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            const string query = @"
                SELECT VehicleTypeID, TypeName
                FROM dbo.PARKING_VEHICLE_TYPE
                WHERE ActiveStatus = 1
                ORDER BY TypeName;";

            using var command = new SqlCommand(query, connection);
            using var reader = command.ExecuteReader();

            while (reader.Read())
            {
                result.Add(new EntryVehicleTypeModel
                {
                    VehicleTypeID = Convert.ToInt32(reader["VehicleTypeID"]),
                    TypeName = reader["TypeName"].ToString() ?? ""
                });
            }

            return result;
        }

        public List<EntrySpaceModel> GetAvailableSpaces(int vehicleTypeId)
        {
            var result = new List<EntrySpaceModel>();

            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            const string query = @"
                SELECT S.SpaceID, S.SpaceCode, S.SpaceName
                FROM dbo.PARKING_SPACE AS S
                INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                    ON VT.VehicleTypeID = S.VehicleTypeID
                WHERE S.VehicleTypeID = @VehicleTypeID
                  AND VT.ActiveStatus = 1
                  AND S.ActiveStatus = 1
                  AND S.SpaceStatus = 'AVAILABLE'
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.PARKING_TICKET AS T
                      WHERE T.SpaceID = S.SpaceID
                        AND T.ExitDateTime IS NULL
                  )
                ORDER BY S.SpaceCode;";

            using var command = new SqlCommand(query, connection);

            command.Parameters.Add("@VehicleTypeID", SqlDbType.Int).Value = vehicleTypeId;

            using var reader = command.ExecuteReader();

            while (reader.Read())
            {
                result.Add(new EntrySpaceModel
                {
                    SpaceID = Convert.ToInt32(reader["SpaceID"]),
                    SpaceCode = reader["SpaceCode"].ToString() ?? "",
                    SpaceName = reader["SpaceName"] == DBNull.Value ? "" : reader["SpaceName"].ToString() ?? ""
                });
            }

            return result;
        }

        public DailyEntryResult CreateDailyEntry(DailyEntryRequestAPI request, int operatorUserId)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand("dbo.PARKING_SP_Daily_Entry", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add("@VehicleNumber", SqlDbType.VarChar, 30).Value = request.VehicleNumber.Trim().ToUpperInvariant();
            command.Parameters.Add("@VehicleTypeID", SqlDbType.Int).Value = request.VehicleTypeID;
            command.Parameters.Add("@OperatorUserID", SqlDbType.Int).Value = operatorUserId;
            command.Parameters.Add("@SpaceID", SqlDbType.Int).Value = request.SpaceID.HasValue ? (object)request.SpaceID.Value : DBNull.Value;
            command.Parameters.Add("@CustomerName", SqlDbType.NVarChar, 200).Value = string.IsNullOrWhiteSpace(request.CustomerName) ? DBNull.Value : (object)request.CustomerName.Trim();
            command.Parameters.Add("@MobileNumber", SqlDbType.VarChar, 20).Value = string.IsNullOrWhiteSpace(request.MobileNumber) ? DBNull.Value : (object)request.MobileNumber.Trim();

            try
            {
                using var reader = command.ExecuteReader();

                if (!reader.Read())
                {
                    throw new InvalidOperationException("Daily entry returned no result.");
                }

                int statusCode = Convert.ToInt32(reader["StatusCode"]);

                var result = new DailyEntryResult
                {
                    StatusCode = statusCode,
                    Message = reader["Message"].ToString() ?? ""
                };

                if (statusCode == 201)
                {
                    result.TicketID = Convert.ToInt32(reader["TicketID"]);
                    result.TicketNumber = reader["TicketNumber"].ToString() ?? "";
                    result.VehicleNumber = reader["VehicleNumber"].ToString() ?? "";
                    result.SpaceID = Convert.ToInt32(reader["SpaceID"]);
                    result.EntryDateTime = DateTime.SpecifyKind(Convert.ToDateTime(reader["EntryDateTime"]), DateTimeKind.Utc);
                }

                return result;
            }
            catch (SqlException exception)
                when (exception.Number == 2601 || exception.Number == 2627)
            {
                return new DailyEntryResult
                {
                    StatusCode = 409,
                    Message = "The vehicle or space already has an open parking visit. " + "Refresh availability before trying again."
                };
            }
            catch (SqlException exception) when (exception.Number == 1205)
            {
                return new DailyEntryResult
                {
                    StatusCode = 409,
                    Message = "Another parking transaction was processed at the same time. " + "Refresh availability and try again."
                };
            }
        }

        public MonthlyEntryResult CreateMonthlyEntry(
    MonthlyEntryRequestAPI request,
    int operatorUserId)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(
                "dbo.PARKING_SP_Monthly_Attendance", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = 3;

            command.Parameters.Add(
                "@VehicleNumber", SqlDbType.VarChar, 30).Value =
                request.VehicleNumber.Trim().ToUpperInvariant();

            command.Parameters.Add(
                "@ExpectedVehicleTypeID", SqlDbType.Int).Value =
                request.VehicleTypeID;

            command.Parameters.Add(
                "@SpaceID", SqlDbType.Int).Value =
                request.SpaceID.HasValue
                    ? (object)request.SpaceID.Value
                    : DBNull.Value;

            command.Parameters.Add(
                "@PerformedByUserID", SqlDbType.Int).Value =
                operatorUserId;

            try
            {
                using var reader = command.ExecuteReader();

                if (!reader.Read())
                {
                    throw new InvalidOperationException(
                        "Monthly entry returned no result.");
                }

                int statusCode = Convert.ToInt32(reader["StatusCode"]);

                var result = new MonthlyEntryResult
                {
                    StatusCode = statusCode,
                    Message = reader["Message"].ToString() ?? ""
                };

                if (statusCode == 201)
                {
                    result.TicketID =
                        Convert.ToInt32(reader["TicketID"]);

                    result.TicketNumber =
                        reader["TicketNumber"].ToString() ?? "";

                    result.VehicleNumber =
                        reader["VehicleNumber"].ToString() ?? "";

                    result.SpaceID =
                        Convert.ToInt32(reader["SpaceID"]);

                    result.EntryDateTime = DateTime.SpecifyKind(
                        Convert.ToDateTime(reader["EntryDateTime"]),
                        DateTimeKind.Utc);

                    result.ContractID =
                        Convert.ToInt32(reader["ContractID"]);

                    result.ContractNumber =
                        reader["ContractNumber"].ToString() ?? "";
                }

                return result;
            }
            catch (SqlException exception)
                when (exception.Number == 2601 || exception.Number == 2627)
            {
                return new MonthlyEntryResult
                {
                    StatusCode = 409,
                    Message =
                        "A conflicting parking record already exists. " +
                        "Check current parking before trying again."
                };
            }
            catch (SqlException exception) when (exception.Number == 1205)
            {
                return new MonthlyEntryResult
                {
                    StatusCode = 409,
                    Message =
                        "Another parking transaction was processed at the same time. " +
                        "Refresh availability and try again."
                };
            }
        }

    }

}