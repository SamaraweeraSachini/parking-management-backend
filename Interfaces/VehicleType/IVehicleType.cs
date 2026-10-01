using ParkingManagement.Models;
using ParkingManagement.Models.VehicleType;

namespace ParkingManagement.Interfaces.VehicleType
{
    public interface IVehicleType
    {
        Response GetVehicleTypes(bool includeInactive = false);

        Response GetVehicleTypeByID(int vehicleTypeID);

        Response AddVehicleType(
            VehicleTypeModel model,
            int performedByUserID);

        Response UpdateVehicleType(
            int vehicleTypeID,
            VehicleTypeModel model,
            int performedByUserID);

        Response DeactivateVehicleType(
            int vehicleTypeID,
            int performedByUserID);

        Response ReactivateVehicleType(
            int vehicleTypeID,
            int performedByUserID);
    }
}