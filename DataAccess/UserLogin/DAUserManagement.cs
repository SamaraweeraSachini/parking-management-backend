using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.DataAccess
{
    public class DAUserManagement : IUserManagement
    {
        private const string ProcedureName = "dbo.PARKING_SP_User";

        public List<UserLoginModel> GetUsers()
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = 3;

            using var reader = command.ExecuteReader();

            var users = new List<UserLoginModel>();

            while (reader.Read())
            {
                users.Add(new UserLoginModel
                {
                    UserID = Convert.ToInt32(reader["UserID"]),
                    FirstName = reader["FirstName"].ToString(),
                    LastName = reader["LastName"].ToString(),
                    Username = reader["Username"].ToString(),
                    UserRole = reader["UserRole"].ToString().Trim(),
                    ActiveStatus = Convert.ToBoolean(reader["ActiveStatus"])
                });
            }

            return users;
        }

        public UserManagementResult CreateUser(
            CreateUserRequestAPI request,
            string passwordHash,
            int performedByUserId)
        {
            return ExecuteChange(2, performedByUserId, command =>
            {
                AddUserDetails(command, request);

                command.Parameters.Add(
                    "@PasswordHash", SqlDbType.NVarChar, 500).Value =
                    passwordHash;
            });
        }

        public UserManagementResult UpdateUser(
            int userId,
            UpdateUserRequestAPI request,
            int performedByUserId)
        {
            return ExecuteChange(5, performedByUserId, command =>
            {
                command.Parameters.Add(
                    "@UserID", SqlDbType.Int).Value = userId;

                AddUserDetails(command, request);
            });
        }

        public UserManagementResult DeactivateUser(
            int userId,
            int performedByUserId)
        {
            return ExecuteChange(6, performedByUserId, command =>
            {
                command.Parameters.Add(
                    "@UserID", SqlDbType.Int).Value = userId;
            });
        }

        private static void AddUserDetails(
            SqlCommand command,
            UpdateUserRequestAPI request)
        {
            command.Parameters.Add(
                "@FirstName", SqlDbType.NVarChar, 100).Value =
                request.FirstName.Trim();

            command.Parameters.Add(
                "@LastName", SqlDbType.NVarChar, 100).Value =
                request.LastName.Trim();

            command.Parameters.Add(
                "@Username", SqlDbType.NVarChar, 100).Value =
                request.Username.Trim();

            command.Parameters.Add(
                "@UserRole", SqlDbType.Char, 1).Value =
                request.UserRole;
        }

        private static UserManagementResult ExecuteChange(
            int actionType,
            int performedByUserId,
            Action<SqlCommand> addParameters)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = actionType;

            command.Parameters.Add(
                "@PerformedByUserID", SqlDbType.Int).Value =
                performedByUserId;

            addParameters(command);

            try
            {
                using var reader = command.ExecuteReader();

                if (!reader.Read())
                {
                    throw new InvalidOperationException(
                        "The user procedure returned no result.");
                }

                int statusCode = Convert.ToInt32(reader["StatusCode"]);

                return new UserManagementResult
                {
                    StatusCode = statusCode,
                    Message = reader["Message"].ToString(),
                    UserId = actionType == 2 && statusCode == 201
                        ? Convert.ToInt32(reader["UserID"])
                        : null
                };
            }
            catch (SqlException exception)
                when (exception.Number == 2601 || exception.Number == 2627)
            {
                return new UserManagementResult
                {
                    StatusCode = 409,
                    Message = "A user with these unique details already exists."
                };
            }
        }
    }
}