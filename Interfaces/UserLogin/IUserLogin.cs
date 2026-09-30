using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface IUserLogin
    {
        //Response Login(UserLoginRequestAPI requestAPI);
        //Response AddUser(UserLoginRequestAPI requestAPI);
        UserLoginModel FindActiveUser(string username);
        UserLoginModel FindActiveUserById(int userId);

        int CreateFirstAdmin(
            string firstName,
            string lastName,
            string username,
            string passwordHash);
    }
}
