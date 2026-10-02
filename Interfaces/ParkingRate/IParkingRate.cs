using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface IParkingRate
    {
        List<ParkingRateModel> GetRates();
        List<RateVehicleTypeModel> GetActiveVehicleTypes();
        List<ApplicableRateModel> GetApplicableRates(int vehicleTypeId);
        ParkingRateResult CreateRate(ParkingRateRequestAPI request, int performedByUserId);
        ParkingRateResult UpdateRate(int rateId, ParkingRateRequestAPI request, int performedByUserId);
    }
}