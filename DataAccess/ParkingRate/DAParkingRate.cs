using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.DataAccess
{
    public class DAParkingRate : IParkingRate
    {
        private const string ProcedureName = "dbo.PARKING_SP_Rate";

        public List<ParkingRateModel> GetRates()
        {
            var rates = new List<ParkingRateModel>();

            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add("@ActionType", SqlDbType.Int).Value = 1;

            command.Parameters.Add("@IncludeInactive", SqlDbType.Bit).Value = true;

            using var reader = command.ExecuteReader();

            while (reader.Read())
            {
                rates.Add(new ParkingRateModel
                {
                    RateID = Convert.ToInt32(reader["RateID"]),
                    VehicleTypeID = Convert.ToInt32(reader["VehicleTypeID"]),
                    RateName = reader["RateName"].ToString() ?? "",
                    RateAmount = Convert.ToDecimal(reader["RateAmount"]),
                    RateUnit = reader["RateUnit"].ToString()?.Trim() ?? "",
                    EffectiveFrom = ReadUtcDate(reader, "EffectiveFrom"),
                    EffectiveTo = ReadNullableUtcDate(reader, "EffectiveTo"),
                    ActiveStatus =Convert.ToBoolean(reader["ActiveStatus"])
                });
            }

            return rates;
        }

        public List<RateVehicleTypeModel> GetActiveVehicleTypes()
        {
            var vehicleTypes = new List<RateVehicleTypeModel>();

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
                vehicleTypes.Add(new RateVehicleTypeModel
                {
                    VehicleTypeID = Convert.ToInt32(reader["VehicleTypeID"]),
                    TypeName = reader["TypeName"].ToString() ?? ""
                });
            }

            return vehicleTypes;
        }

        public List<ApplicableRateModel> GetApplicableRates(int vehicleTypeId)
        {
            var rates = new List<ApplicableRateModel>();

            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add("@ActionType", SqlDbType.Int).Value = 7;
            command.Parameters.Add("@VehicleTypeID", SqlDbType.Int).Value = vehicleTypeId;

            using var reader = command.ExecuteReader();

            while (reader.Read())
            {
                // Action 7 returns a status row for invalid vehicle types.
                if (HasColumn(reader, "StatusCode"))
                {
                    int statusCode = Convert.ToInt32(reader["StatusCode"]);

                    string message = reader["Message"].ToString() ?? "";

                    if (statusCode == 404)
                    {
                        throw new KeyNotFoundException(message);
                    }

                    throw new ArgumentException(message);
                }

                rates.Add(new ApplicableRateModel
                {
                    RateID = Convert.ToInt32(reader["RateID"]),
                    VehicleTypeID = Convert.ToInt32(reader["VehicleTypeID"]),
                    RateName = reader["RateName"].ToString() ?? "",
                    RateAmount = Convert.ToDecimal(reader["RateAmount"]),
                    RateUnit = reader["RateUnit"].ToString()?.Trim() ?? "",
                    EffectiveFrom = ReadUtcDate(reader, "EffectiveFrom"),
                    EffectiveTo = ReadNullableUtcDate(reader, "EffectiveTo")
                });
            }

            return rates;
        }

        public ParkingRateResult CreateRate(ParkingRateRequestAPI request, int performedByUserId)
        {
            return ExecuteRateWrite(3, null, request, performedByUserId);
        }

        public ParkingRateResult UpdateRate(int rateId, ParkingRateRequestAPI request, int performedByUserId)
        {
            return ExecuteRateWrite(4, rateId, request, performedByUserId);
        }

        private ParkingRateResult ExecuteRateWrite(int actionType, int? rateId, ParkingRateRequestAPI request, int performedByUserId)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add("@ActionType", SqlDbType.Int).Value = actionType;
            command.Parameters.Add("@RateID", SqlDbType.Int).Value = rateId.HasValue ? (object)rateId.Value : DBNull.Value;
            command.Parameters.Add("@VehicleTypeID", SqlDbType.Int).Value = request.VehicleTypeID;
            command.Parameters.Add("@RateName", SqlDbType.NVarChar, 100).Value = request.RateName.Trim();

            var amountParameter = command.Parameters.Add("@RateAmount", SqlDbType.Decimal);

            amountParameter.Precision = 12;
            amountParameter.Scale = 2;
            amountParameter.Value = request.RateAmount!.Value;

            command.Parameters.Add("@RateUnit", SqlDbType.VarChar, 20).Value = request.RateUnit;
            command.Parameters.Add("@EffectiveFrom", SqlDbType.DateTime2).Value = request.EffectiveFrom.HasValue ? (object)request.EffectiveFrom.Value.UtcDateTime : DBNull.Value;
            command.Parameters.Add("@EffectiveTo", SqlDbType.DateTime2).Value = request.EffectiveTo.HasValue ? (object)request.EffectiveTo.Value.UtcDateTime : DBNull.Value;
            command.Parameters.Add("@PerformedByUserID", SqlDbType.Int).Value = performedByUserId;

            try
            {
                using var reader = command.ExecuteReader();

                if (!reader.Read())
                {
                    throw new InvalidOperationException("The rate procedure returned no result.");
                }

                return new ParkingRateResult
                {
                    StatusCode = Convert.ToInt32(reader["StatusCode"]),
                    Message = reader["Message"].ToString() ?? "",
                    RateID = HasColumn(reader, "RateID") && reader["RateID"] != DBNull.Value ? Convert.ToInt32(reader["RateID"]) : rateId
                };
            }
            catch (SqlException exception)
                when (exception.Number == 2601 || exception.Number == 2627)
            {
                return new ParkingRateResult
                {
                    StatusCode = 409,
                    Message = "An active rate already exists for this " + "vehicle type and unit."
                };
            }
        }

        private static DateTime ReadUtcDate(SqlDataReader reader, string columnName)
        {
            return DateTime.SpecifyKind(Convert.ToDateTime(reader[columnName]), DateTimeKind.Utc);
        }

        private static DateTime? ReadNullableUtcDate(SqlDataReader reader, string columnName)
        {
            return reader[columnName] == DBNull.Value ? null : ReadUtcDate(reader, columnName);
        }

        private static bool HasColumn(SqlDataReader reader, string columnName)
        {
            for (int index = 0; index < reader.FieldCount; index++)
            {
                if (string.Equals(reader.GetName(index), columnName, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return false;
        }
    }
}