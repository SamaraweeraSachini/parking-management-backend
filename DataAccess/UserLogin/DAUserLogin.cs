using System.Data;
using Microsoft.Data.SqlClient;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.DataAccess
{
    public class DAUserLogin : IUserLogin
    {
        private const string ProcedureName = "dbo.PARKING_SP_User";

        public UserLoginModel FindActiveUser(string username)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = 1;

            command.Parameters.Add(
                "@Username", SqlDbType.NVarChar, 100).Value = username;

            using var reader = command.ExecuteReader();

            if (!reader.Read())
                return null;

            return MapUser(reader, includePasswordHash: true);
        }

        public UserLoginModel FindActiveUserById(int userId)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = 4;

            command.Parameters.Add(
                "@UserID", SqlDbType.Int).Value = userId;

            using var reader = command.ExecuteReader();

            if (!reader.Read())
                return null;

            var user = MapUser(reader, includePasswordHash: false);

            return user.ActiveStatus ? user : null;
        }

        public int CreateFirstAdmin(
            string firstName,
            string lastName,
            string username,
            string passwordHash)
        {
            using var database = new DBconnect("PARKING");
            using var connection = database.GetOpenConnection();

            using var command = new SqlCommand(ProcedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@ActionType", SqlDbType.Int).Value = 2;

            command.Parameters.Add(
                "@FirstName", SqlDbType.NVarChar, 100).Value = firstName;

            command.Parameters.Add(
                "@LastName", SqlDbType.NVarChar, 100).Value = lastName;

            command.Parameters.Add(
                "@Username", SqlDbType.NVarChar, 100).Value = username;

            command.Parameters.Add(
                "@PasswordHash", SqlDbType.NVarChar, 500).Value = passwordHash;

            command.Parameters.Add(
                "@UserRole", SqlDbType.Char, 1).Value = "A";

            using var reader = command.ExecuteReader();

            if (!reader.Read())
            {
                throw new InvalidOperationException(
                    "The user procedure returned no result.");
            }

            int statusCode =
                Convert.ToInt32(reader["StatusCode"]);

            if (statusCode != 201)
            {
                throw new InvalidOperationException(
                    reader["Message"].ToString());
            }

            return Convert.ToInt32(reader["UserID"]);
        }

        private static UserLoginModel MapUser(
            SqlDataReader reader,
            bool includePasswordHash)
        {
            return new UserLoginModel
            {
                UserID = Convert.ToInt32(reader["UserID"]),
                FirstName = reader["FirstName"].ToString(),
                LastName = reader["LastName"].ToString(),
                Username = reader["Username"].ToString(),
                UserRole = reader["UserRole"].ToString().Trim(),
                ActiveStatus = Convert.ToBoolean(reader["ActiveStatus"]),

                PasswordHash = includePasswordHash
                    ? reader["PasswordHash"].ToString()
                    : ""
            };
        }
    }
}