using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Interfaces.VehicleType;
using ParkingManagement.Models;
using ParkingManagement.Models.VehicleType;

namespace ParkingManagement.DataAccess
{
    public class DAVehicleType : IVehicleType
    {
        private const string ProcedureName =
            "dbo.PARKING_SP_Vehicle_Type";

        public Response GetVehicleTypes(bool includeInactive = false)
        {
            return Execute(
                actionType: 1,
                includeInactive: includeInactive);
        }

        public Response GetVehicleTypeByID(int vehicleTypeID)
        {
            return Execute(
                actionType: 2,
                vehicleTypeID: vehicleTypeID);
        }

        public Response AddVehicleType(
            VehicleTypeModel model,
            int performedByUserID)
        {
            return Execute(
                actionType: 3,
                model: model,
                performedByUserID: performedByUserID);
        }

        public Response UpdateVehicleType(
            int vehicleTypeID,
            VehicleTypeModel model,
            int performedByUserID)
        {
            return Execute(
                actionType: 4,
                vehicleTypeID: vehicleTypeID,
                model: model,
                performedByUserID: performedByUserID);
        }

        public Response DeactivateVehicleType(
            int vehicleTypeID,
            int performedByUserID)
        {
            return Execute(
                actionType: 5,
                vehicleTypeID: vehicleTypeID,
                performedByUserID: performedByUserID);
        }

        public Response ReactivateVehicleType(
            int vehicleTypeID,
            int performedByUserID)
        {
            return Execute(
                actionType: 6,
                vehicleTypeID: vehicleTypeID,
                performedByUserID: performedByUserID);
        }

        private Response Execute(
            int actionType,
            int? vehicleTypeID = null,
            VehicleTypeModel model = null,
            int? performedByUserID = null,
            bool includeInactive = false)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(
                ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = actionType;

            command.Parameters.Add(
                "@VehicleTypeID", SqlDbType.Int).Value =
                (object)vehicleTypeID ?? DBNull.Value;

            command.Parameters.Add(
                "@TypeName", SqlDbType.NVarChar, 100).Value =
                (object)model?.TypeName?.Trim() ?? DBNull.Value;

            command.Parameters.Add(
                "@Description", SqlDbType.NVarChar, 500).Value =
                (object)model?.Description?.Trim() ?? DBNull.Value;

            command.Parameters.Add(
                "@PerformedByUserID", SqlDbType.Int).Value =
                (object)performedByUserID ?? DBNull.Value;

            command.Parameters.Add(
                "@IncludeInactive", SqlDbType.Bit).Value =
                includeInactive;

            using var reader = command.ExecuteReader();

            var vehicleTypes = new List<VehicleTypeModel>();
            Response operationResult = null;

            // Read every result set, including Action 2's
            // not-found status after an empty data result.
            do
            {
                bool isStatusResult =
                    HasColumn(reader, "StatusCode");

                while (reader.Read())
                {
                    if (isStatusResult)
                    {
                        operationResult = new Response
                        {
                            StatusCode = Convert.ToInt32(
                                reader["StatusCode"]),

                            Result = reader["Message"].ToString()
                        };

                        if (HasColumn(reader, "VehicleTypeID") &&
                            reader["VehicleTypeID"] != DBNull.Value)
                        {
                            operationResult.ResultSet = new
                            {
                                VehicleTypeID = Convert.ToInt32(
                                    reader["VehicleTypeID"])
                            };
                        }
                    }
                    else
                    {
                        vehicleTypes.Add(MapVehicleType(reader));
                    }
                }
            }
            while (reader.NextResult());

            // Validation errors and successful writes.
            if (operationResult != null)
            {
                return operationResult;
            }

            // List operation: an empty list is still successful.
            if (actionType == 1)
            {
                return new Response
                {
                    StatusCode = 200,
                    Result = "Vehicle types retrieved successfully.",
                    ResultSet = vehicleTypes
                };
            }

            // Single-record operation.
            if (actionType == 2)
            {
                if (vehicleTypes.Count == 0)
                {
                    return new Response
                    {
                        StatusCode = 404,
                        Result = "Vehicle type not found."
                    };
                }

                return new Response
                {
                    StatusCode = 200,
                    Result = "Vehicle type retrieved successfully.",
                    ResultSet = vehicleTypes[0]
                };
            }

            throw new InvalidOperationException(
                "The vehicle type procedure returned no operation status.");
        }

        private static VehicleTypeModel MapVehicleType(
            SqlDataReader reader)
        {
            return new VehicleTypeModel
            {
                VehicleTypeID = Convert.ToInt32(
                    reader["VehicleTypeID"]),

                TypeName = reader["TypeName"].ToString(),

                Description = reader["Description"] == DBNull.Value
                    ? null
                    : reader["Description"].ToString(),

                ActiveStatus = Convert.ToBoolean(
                    reader["ActiveStatus"]),

                CreatedAt = Convert.ToDateTime(
                    reader["CreatedAt"]),

                CreatedBy = reader["CreatedBy"] == DBNull.Value
                    ? (int?)null
                    : Convert.ToInt32(reader["CreatedBy"]),

                UpdatedAt = reader["UpdatedAt"] == DBNull.Value
                    ? (DateTime?)null
                    : Convert.ToDateTime(reader["UpdatedAt"]),

                UpdatedBy = reader["UpdatedBy"] == DBNull.Value
                    ? (int?)null
                    : Convert.ToInt32(reader["UpdatedBy"])
            };
        }

        private static bool HasColumn(
            SqlDataReader reader,
            string columnName)
        {
            for (int index = 0; index < reader.FieldCount; index++)
            {
                if (string.Equals(
                    reader.GetName(index),
                    columnName,
                    StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return false;
        }
    }
}