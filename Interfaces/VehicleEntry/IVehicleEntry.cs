using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface IVehicleEntry
    {
        List<EntryVehicleTypeModel> GetActiveVehicleTypes();
        List<EntrySpaceModel> GetAvailableSpaces(int vehicleTypeId);
        DailyEntryResult CreateDailyEntry(DailyEntryRequestAPI request, int operatorUserId);
        MonthlyEntryResult CreateMonthlyEntry(MonthlyEntryRequestAPI request, int operatorUserId);
    }
}