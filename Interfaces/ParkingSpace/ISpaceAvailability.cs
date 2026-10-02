using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface ISpaceAvailability
    {
        List<SpaceAvailabilityModel> GetSpaces();
    }
}
