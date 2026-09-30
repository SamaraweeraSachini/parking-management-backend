using ParkingManagement.Models;

namespace ParkingManagement.Interfaces
{
    public interface ISupplierDetails
    {
        Response GetSuppliers(SupplierRequestAPI requestAPI);
        Response GetSuppliersByID(SupplierRequestAPI requestAPI);
        Response AddSupplier(SupplierRequestAPI requestAPI);
        Response UpdateSupplierDetails(SupplierRequestAPI requestAPI);
    }
}
