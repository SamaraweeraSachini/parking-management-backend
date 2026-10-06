using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface ICurrentParking
    {
        List<CurrentParkingModel> GetCurrentParking(string searchTerm);
    }
}