using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface IUserManagement
    {
        List<UserLoginModel> GetUsers();

        UserManagementResult CreateUser(
            CreateUserRequestAPI request,
            string passwordHash,
            int performedByUserId);

        UserManagementResult UpdateUser(
            int userId,
            UpdateUserRequestAPI request,
            int performedByUserId);

        UserManagementResult DeactivateUser(
            int userId,
            int performedByUserId);
    }
}