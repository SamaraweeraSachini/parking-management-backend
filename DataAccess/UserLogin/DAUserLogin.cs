using System;
using System.Data;
using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;
using ParkingManagement.Static;

namespace ParkingManagement.DataAccess
{
    public class DAUserLogin : IUserLogin
    {
        private const string ProcedureName = "dbo.PARKING_SP_User";

        public UserLoginModel FindActiveUser(string username)
        {
            UserProcedureRequestAPI requestAPI = new UserProcedureRequestAPI
                {
                    ActionType = 1,
                    Username = username
                };

            using (var dbConnect = new DBconnect("PARKING"))
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                EnsureProcedureSucceeded(res, nameof(FindActiveUser));

                if (res.ResultDataTable == null || res.ResultDataTable.Rows.Count == 0)
                {
                    return null;
                }

                UserLoginModel user = MapUser(res.ResultDataTable.Rows[0], includePasswordHash: true);

                return user.ActiveStatus ? user : null;
            }
        }

        public UserLoginModel FindActiveUserById(int userId)
        {
            UserProcedureRequestAPI requestAPI = new UserProcedureRequestAPI
                {
                    ActionType = 4,
                    UserID = userId
                };

            using (var dbConnect = new DBconnect("PARKING"))
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                EnsureProcedureSucceeded(res, nameof(FindActiveUserById));

                if (res.ResultDataTable == null || res.ResultDataTable.Rows.Count == 0)
                {
                    return null;
                }

                UserLoginModel user = MapUser(
                        res.ResultDataTable.Rows[0],
                        includePasswordHash: false);

                return user.ActiveStatus ? user : null;
            }
        }

        public int CreateFirstAdmin(
            string firstName,
            string lastName,
            string username,
            string passwordHash)
        {
            UserProcedureRequestAPI requestAPI = new UserProcedureRequestAPI
                {
                    ActionType = 2,
                    FirstName = firstName,
                    LastName = lastName,
                    Username = username,
                    PasswordHash = passwordHash,
                    UserRole = "A"
                };

            using (var dbConnect = new DBconnect("PARKING"))
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                EnsureProcedureSucceeded(res, nameof(CreateFirstAdmin));

                if (res.ResultDataTable == null || res.ResultDataTable.Rows.Count == 0)
                {
                    throw new InvalidOperationException("The user procedure returned no result.");
                }

                DataRow row = res.ResultDataTable.Rows[0];

                if (Convert.ToInt32(row["StatusCode"]) != 201)
                {
                    throw new InvalidOperationException(row["Message"].ToString());
                }

                return Convert.ToInt32(row["UserID"]);
            }
        }

        private static void EnsureProcedureSucceeded(ProcedureDBModel result, string methodName)
        {
            if (result.ResultStatusCode == "1")
            {
                return;
            }

            string message = result.Result;

            // Preserve the procedure's detailed validation message.
            if (result.ResultDataTable != null &&
                result.ResultDataTable.Rows.Count > 0 &&
                result.ResultDataTable.Columns.Contains("Message"))
            {
                message = result.ResultDataTable.Rows[0]["Message"].ToString();
            }

            LogHandler.WriteToLog(
                result.ExceptionMessage,
                message,
                methodName);

            throw new InvalidOperationException(
                string.IsNullOrWhiteSpace(message)
                    ? "The user database operation failed."
                    : message);
        }

        private static UserLoginModel MapUser(DataRow row, bool includePasswordHash)
        {
            return new UserLoginModel
            {
                UserID = Convert.ToInt32(row["UserID"]),
                FirstName = row["FirstName"].ToString(),
                LastName = row["LastName"].ToString(),
                Username = row["Username"].ToString(),
                UserRole = row["UserRole"].ToString().Trim(),
                ActiveStatus = Convert.ToBoolean(row["ActiveStatus"]),

                PasswordHash = includePasswordHash
                    ? row["PasswordHash"].ToString()
                    : ""
            };
        }
    }
}